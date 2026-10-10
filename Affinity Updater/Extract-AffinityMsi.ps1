#Requires -Version 5.1
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
