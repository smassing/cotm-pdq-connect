#Requires -Version 5.1
<#
.SYNOPSIS
Installs or upgrades Affinity Enterprise x64 through PDQ.
.DESCRIPTION
Standalone: paste the entire script into a PDQ PowerShell step or run as a file.
Uses WinGet only to query versions. Downloads the Enterprise EXE, verifies its
Canva signature, extracts its MSI, and installs without UI or automatic restart.
Run as SYSTEM or an elevated administrator in 64-bit PowerShell on x64 Windows.
Exit codes: 0 = current/installed/check complete; 1 = failure; 3010 = reboot required.
.PARAMETER CheckOnly
Queries available and installed versions without downloading or installing.
.PARAMETER KeepInstaller
Keeps the EXE and MSI after success for troubleshooting. Failures retain them.
#>
[CmdletBinding()]
param (
    [switch]$CheckOnly,
    [switch]$KeepInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:AffinityExe = Join-Path $env:ProgramFiles 'Affinity\Affinity\Affinity.exe'
$script:DownloadUrl = 'https://downloads.affinity.studio/Affinity%20x64.exe'

function Write-AffinityLog {
    param([string]$Message)
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function ConvertTo-AffinityVersion {
    param([string]$Value)
    if ($Value -notmatch '^\d+\.\d+(?:\.\d+){0,2}$') {
        throw "Unsupported version value: '$Value'"
    }
    $v = [version]$Value
    return [version]::new($v.Major, $v.Minor, [Math]::Max(0, $v.Build), [Math]::Max(0, $v.Revision))
}

function Get-AffinityInstalledVersion {
    if (-not (Test-Path -LiteralPath $script:AffinityExe -PathType Leaf)) { return $null }
    $v = (Get-Item -LiteralPath $script:AffinityExe).VersionInfo.FileVersionRaw
    if ($null -eq $v -or $v.Major -lt 3) {
        throw "Cannot determine an Affinity 3+ version from $script:AffinityExe"
    }
    return ConvertTo-AffinityVersion $v.ToString()
}

function Resolve-AffinityWinget {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    # Same SYSTEM-context discovery approach as the repository's PDQ scripts.
    $packages = @(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'winget.exe') } |
        Sort-Object { [version](($_.Name -split '_')[1]) } -Descending)
    if ($packages.Count -gt 0) { return Join-Path $packages[0].FullName 'winget.exe' }
    throw 'WinGet was not found on PATH or in the x64 Desktop App Installer folders.'
}

function Get-AffinityLatestVersion {
    $winget = Resolve-AffinityWinget
    Write-AffinityLog "WinGet: $winget"
    $output = @(& $winget show --id Canva.Affinity --exact --versions --source winget --accept-source-agreements --disable-interactivity 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "WinGet version query failed (exit $code): $($output -join [Environment]::NewLine)"
    }
    # Numeric version rows avoid parsing localized 'Version:' labels or progress bars.
    $clean = ($output -join "`n") -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $versions = @(foreach ($line in ($clean -split '[\r\n]+')) {
        if ($line.Trim() -match '^\d+\.\d+(?:\.\d+){0,2}$') {
            ConvertTo-AffinityVersion $line.Trim()
        }
    })
    if ($versions.Count -eq 0) { throw "WinGet returned no numeric Affinity versions: $clean" }
    return $versions | Sort-Object -Descending | Select-Object -First 1
}

function Assert-AffinityClosed {
    if (Get-Process -Name Affinity -ErrorAction SilentlyContinue) {
        throw 'Affinity is running. Close it and retry; the updater does not terminate user sessions.'
    }
}

function Assert-AffinityAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Run this script as SYSTEM or from an elevated administrator PowerShell session.'
        }
    } finally { $identity.Dispose() }
}

function New-AffinityRunDirectory {
    $directory = Join-Path $env:ProgramData ('COTM\AffinityUpdater\' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $directory)
    # Only administrators and SYSTEM may change staged installers.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl',
            'ContainerInherit, ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $directory -AclObject $acl
    return $directory
}

function Receive-AffinityInstaller {
    param([string]$Path)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Write-AffinityLog "Downloading Enterprise installer (attempt $attempt of 3)."
            $oldProgress = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $script:DownloadUrl -OutFile $Path -UseBasicParsing -TimeoutSec 900
            } finally { $ProgressPreference = $oldProgress }
            return
        } catch {
            if ($attempt -eq 3) { throw }
            Write-AffinityLog "Download failed: $($_.Exception.Message). Retrying."
            Start-Sleep -Seconds 5
        }
    }
}

# Embedded extraction helper: standalone PDQ deployment needs no companion file.
function Invoke-AffinityMsiExtraction {
<#
.SYNOPSIS
Extracts and inspects the MSI embedded in a signed Affinity Enterprise EXE.
.DESCRIPTION
Does not launch the EXE or install the MSI. Uses Windows resource APIs to read
the EXE as data, and Windows Installer COM to inspect the extracted package.
Run in full-language Windows PowerShell 5.1 or PowerShell 7 on Windows.
.EXAMPLE
.\Extract-AffinityMsi.ps1 -InstallerPath "$env:USERPROFILE\Downloads\Affinity x64.exe" -OutputPath "$env:TEMP\Affinity-extracted.msi"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $InstallerPath).ProviderPath
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $destination) {
    throw "Output already exists; choose a new path: $destination"
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $destination) -PathType Container)) {
    throw 'The output directory must already exist.'
}

$signature = Get-AuthenticodeSignature -LiteralPath $source
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.GetNameInfo(
        [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Canva') {
    throw 'The installer must have a valid Authenticode signature from Canva.'
}
Write-Host "Verified installer publisher: $($signature.SignerCertificate.Subject)"

if (-not ('Cotm.AffinityMsiResources' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace Cotm {
    public static class AffinityMsiResources {
        private delegate bool TypeCallback(IntPtr module, IntPtr type, IntPtr param);
        private delegate bool NameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumResourceTypesW(IntPtr module, TypeCallback callback, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumResourceNamesW(IntPtr module, IntPtr type, NameCallback callback, IntPtr param);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr resource);

        public static long Extract(string source, string destination) {
            // DATAFILE_EXCLUSIVE | IMAGE_RESOURCE: read resources without running code.
            IntPtr module = LoadLibraryExW(source, IntPtr.Zero, 0x60);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                IntPtr payload = IntPtr.Zero;
                uint payloadSize = 0;
                int candidates = 0;
                Exception callbackError = null;
                byte[] magic = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
                NameCallback names = delegate(IntPtr m, IntPtr type, IntPtr name, IntPtr p) {
                    try {
                        IntPtr resource = FindResourceW(m, name, type);
                        if (resource == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                        uint size = SizeofResource(m, resource);
                        if (size < magic.Length) return true;
                        IntPtr loaded = LoadResource(m, resource);
                        if (loaded == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                        IntPtr data = LockResource(loaded);
                        if (data == IntPtr.Zero) throw new InvalidDataException("Cannot read resource.");
                        for (int i = 0; i < magic.Length; i++)
                            if (Marshal.ReadByte(data, i) != magic[i]) return true;
                        candidates++;
                        payload = data;
                        payloadSize = size;
                        return true;
                    } catch (Exception e) { callbackError = e; return false; }
                };
                TypeCallback types = delegate(IntPtr m, IntPtr type, IntPtr p) {
                    if (!EnumResourceNamesW(m, type, names, IntPtr.Zero)) {
                        if (callbackError == null) callbackError = new Win32Exception(Marshal.GetLastWin32Error());
                        return false;
                    }
                    return true;
                };
                bool enumerated = EnumResourceTypesW(module, types, IntPtr.Zero);
                if (callbackError != null) throw callbackError;
                if (!enumerated) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (candidates != 1)
                    throw new InvalidDataException("Expected one compound-file MSI resource; found " + candidates + ".");
                if (payloadSize > Int32.MaxValue)
                    throw new InvalidDataException("Embedded resource exceeds supported size.");
                using (FileStream output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write)) {
                    byte[] buffer = new byte[1024 * 1024];
                    int offset = 0;
                    while (offset < payloadSize) {
                        int count = (int)Math.Min((long)buffer.Length, (long)payloadSize - offset);
                        Marshal.Copy(IntPtr.Add(payload, offset), buffer, 0, count);
                        output.Write(buffer, 0, count);
                        offset += count;
                    }
                }
                return payloadSize;
            } finally { FreeLibrary(module); }
        }
    }
}
'@
}

$installer = $database = $view = $record = $null
$extracted = $false
try {
    $bytes = [Cotm.AffinityMsiResources]::Extract($source, $destination)
    $extracted = $true
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($destination, 0)
    $properties = @{}
    $view = $database.OpenView('SELECT `Property`, `Value` FROM `Property`')
    [void]$view.Execute()
    while ($null -ne ($record = $view.Fetch())) {
        try { $properties[$record.StringData(1)] = $record.StringData(2) }
        finally {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
            $record = $null
        }
    }
    if ($properties.ProductName -ne 'Affinity' -or $properties.Manufacturer -ne 'Canva') {
        throw "Unexpected MSI identity: $($properties.Manufacturer) / $($properties.ProductName)"
    }
    $version = [version]$properties.ProductVersion
    if ($version.Major -lt 3) { throw "Unexpected Affinity version: $version" }
    [pscustomobject]@{
        MsiPath = $destination
        ProductName = $properties.ProductName
        Manufacturer = $properties.Manufacturer
        ProductVersion = $version.ToString()
        ProductCode = $properties.ProductCode
        SizeBytes = $bytes
        SHA256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }
} catch {
    # Retain a failed extraction for inspection; never install it.
    if ($extracted) { Write-Warning "MSI validation failed. Extracted file retained at $destination" }
    throw
} finally {
    if ($null -ne $view) { [void]$view.Close() }
    foreach ($comObject in @($record, $view, $database, $installer)) {
        if ($null -ne $comObject) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
        }
    }
}

}

function Start-AffinityMsi {
    param([string]$MsiPath, [string]$LogPath)
    $arguments = '/i "{0}" /qn /norestart INSTALL_DESKTOP_SHORTCUT_PROPERTY="#0" /L*v "{1}"' -f $MsiPath, $LogPath
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
    return $process.ExitCode
}

function Invoke-AffinityUpdate {
    param([switch]$OnlyCheck, [switch]$RetainInstaller)
    $mutex = $null
    $hasMutex = $false
    $runDirectory = $null
    $transcribing = $false
    $success = $false
    try {
        if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
            throw 'This updater requires 64-bit PowerShell on x64 Windows; ARM64 is not supported.'
        }
        $latest = Get-AffinityLatestVersion
        $installed = Get-AffinityInstalledVersion
        Write-AffinityLog "Available WinGet version: $latest"
        Write-AffinityLog "Installed Enterprise version: $(if ($null -eq $installed) { 'Missing' } else { $installed })"
        if ($null -ne $installed -and $installed -ge $latest) {
            Write-AffinityLog 'Installed version is equal or newer. No download or installation needed.'
            return 0
        }
        if ($OnlyCheck) {
            Write-AffinityLog 'Installation or upgrade is needed. CheckOnly: no download or installation performed.'
            return 0
        }
        Assert-AffinityAdministrator
        $mutex = New-Object Threading.Mutex($false, 'Global\COTM-AffinityUpdater')
        try { $hasMutex = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $hasMutex = $true }
        if (-not $hasMutex) { throw 'Another Affinity updater is already running.' }
        Assert-AffinityClosed

        $runDirectory = New-AffinityRunDirectory
        Start-Transcript -Path (Join-Path $runDirectory 'updater.log') | Out-Null
        $transcribing = $true
        Write-AffinityLog "Run directory and logs: $runDirectory"
        Write-AffinityLog "Available: $latest; previously installed: $installed"
        $exePath = Join-Path $runDirectory 'Affinity-x64.exe'
        $msiPath = Join-Path $runDirectory 'Affinity.msi'
        $msiLog = Join-Path $runDirectory 'msi-install.log'
        Receive-AffinityInstaller -Path $exePath
        $package = Invoke-AffinityMsiExtraction -InstallerPath $exePath -OutputPath $msiPath
        $target = ConvertTo-AffinityVersion $package.ProductVersion
        Write-AffinityLog "Verified Enterprise MSI version: $target; SHA256: $($package.SHA256)"
        if ($target -lt $latest) {
            throw "Enterprise download ($target) is older than WinGet ($latest). Retry after the release sources agree."
        }
        if ($target -gt $latest) {
            Write-AffinityLog 'Enterprise download is ahead of WinGet; using the verified Enterprise version.'
        }
        # Recheck after download: another installer may have changed the application.
        $installed = Get-AffinityInstalledVersion
        if ($null -ne $installed -and $installed -ge $target) {
            Write-AffinityLog 'Installed version is now equal or newer than the MSI. Skipping installation.'
            $success = $true
            return 0
        }
        Assert-AffinityClosed
        Write-AffinityLog "Installing Affinity $target. MSI log: $msiLog"
        $code = Start-AffinityMsi -MsiPath $msiPath -LogPath $msiLog
        Write-AffinityLog "MSI exit code: $code"
        if ($code -notin @(0, 3010)) { throw "MSI installation failed (exit $code). See $msiLog" }
        $actual = Get-AffinityInstalledVersion
        if ($null -eq $actual -or $actual -lt $target) {
            throw "Post-install verification failed: expected at least $target; found '$actual'. MSI exit: $code. See $msiLog"
        }
        Write-AffinityLog "Verified installed executable version: $actual"
        if ($code -eq 3010) { Write-AffinityLog 'Installation succeeded; Windows reports that a reboot is required.' }
        $success = $true
        return $code
    } catch {
        Write-AffinityLog "FAILED: $($_.Exception.Message)"
        if ($runDirectory) { Write-AffinityLog "Retained troubleshooting files: $runDirectory" }
        return 1
    } finally {
        if ($transcribing) {
            try { Stop-Transcript | Out-Null } catch { Write-Warning "Cannot stop transcript: $_" }
        }
        if ($success -and -not $RetainInstaller -and $runDirectory) {
            # Remove only the two payloads from this invocation; retain all logs.
            foreach ($name in @('Affinity-x64.exe', 'Affinity.msi')) {
                try { Remove-Item -LiteralPath (Join-Path $runDirectory $name) -ErrorAction Stop }
                catch { Write-Warning "Could not remove staged $name : $_" }
            }
        }
        if ($hasMutex) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}

exit (Invoke-AffinityUpdate -OnlyCheck:$CheckOnly -RetainInstaller:$KeepInstaller)
