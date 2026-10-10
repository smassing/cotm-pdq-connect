<# 
MSP Auto-Update (SYSTEM-friendly)

Sequence:
1) Get current MSP Windows version/build + download URL from website
2) Read HKLM:\Software\COTM\MSP\Version (REG_SZ)
3) Compare and decide whether to install
4) If install: download EXE to C:\Temp and run silently; capture exit code
5) If exit code 0: write website version to registry; else exit with installer code
6) Exit 0

All steps write to console.
#>

$ErrorActionPreference = "Stop"

# -------- Defaults (edit if needed) --------
$DownloadPageUrl = "https://ministryschedulerpro.com/download"
$RegPath         = "HKLM:\Software\COTM\MSP"
$RegValueName    = "Version"
$TempDir         = "C:\Temp"
# ------------------------------------------

function Write-Step([string]$msg) {
  Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

function Get-MspWindowsInfo([string]$Url) {
  Write-Step "Step 1: Fetching MSP download page: $Url"

  $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{
    "User-Agent"    = "MSP-AutoUpdate/1.0"
    "Cache-Control" = "no-cache"
    "Pragma"        = "no-cache"
  }

  $html = $resp.Content

  # Anchor to the Windows card and extract EXE download URL + version/build
  $pattern = '(?is)<h3[^>]*>.*?Windows.*?</h3>.*?data-download-url="(?<exe>https://[^"]+\.exe)".*?Ministry\s+Scheduler\s+Pro\s+(?<full>v\d+(?:\.\d+){1,3}\s*\(Build\s*\d+\))'
  $m = [regex]::Match($html, $pattern)

  if (-not $m.Success) { return $null }

  [pscustomobject]@{
    VersionString = $m.Groups["full"].Value.Trim()   # "v8.2.1 (Build 9)"
    DownloadUrl   = $m.Groups["exe"].Value.Trim()    # "https://...Installer.exe"
  }
}

function Get-InstalledVersionFromRegistry([string]$Path, [string]$Name) {
  Write-Step "Step 2: Reading registry value: $Path\$Name"

  if (-not (Test-Path $Path)) {
    Write-Step "Registry path does not exist: $Path"
    return $null
  }

  try {
    $val = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    if ([string]::IsNullOrWhiteSpace($val)) { return $null }
    return [string]$val
  } catch {
    Write-Step "Registry value not found (or unreadable): $($_.Exception.Message)"
    return $null
  }
}

function Ensure-Directory([string]$Path) {
  if (-not (Test-Path $Path)) {
    Write-Step "Creating directory: $Path"
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  } else {
    Write-Step "Directory exists: $Path"
  }
}

function Download-File([string]$Url, [string]$DestinationPath) {
  Write-Step "Step 4: Downloading installer"
  Write-Step "Download URL: $Url"
  Write-Step "Saving to: $DestinationPath"

  Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $DestinationPath -Headers @{
    "User-Agent"    = "MSP-AutoUpdate/1.0"
    "Cache-Control" = "no-cache"
    "Pragma"        = "no-cache"
  }

  if (-not (Test-Path $DestinationPath)) {
    throw "Download failed: file not found after download: $DestinationPath"
  }

  $len = (Get-Item $DestinationPath).Length
  Write-Step "Downloaded installer size: $len bytes"
}

function Run-Installer([string]$InstallerPath) {
  $argumentList = "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"

  Write-Step "Step 4: Executing installer"
  Write-Step "Command: `"$InstallerPath`" $argumentList"

  $proc = Start-Process -FilePath $InstallerPath -ArgumentList $argumentList -Wait -PassThru
  Write-Step "Installer completed with exit code: $($proc.ExitCode)"
  return [int]$proc.ExitCode
}


function Set-RegistryVersion([string]$Path, [string]$Name, [string]$Value) {
  Write-Step "Step 5: Writing registry value: $Path\$Name = '$Value'"

  if (-not (Test-Path $Path)) {
    Write-Step "Registry path missing; creating: $Path"
    New-Item -Path $Path -Force | Out-Null
  }

  # REG_SZ
  New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
  Write-Step "Registry updated successfully."
}

# ---------------- Main flow ----------------
try {
  Write-Step "MSP Auto-Update starting (running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name))"

  # Step 1
  $webInfo = Get-MspWindowsInfo $DownloadPageUrl
  if ($null -eq $webInfo) {
    Write-Step "ERROR: Step 1 did not return a Windows version/download URL. Exiting with error code 10."
    exit 10
  }

  Write-Step "Step 1 result: Website version = '$($webInfo.VersionString)'"
  Write-Step "Step 1 result: Website download URL = '$($webInfo.DownloadUrl)'"

  # Step 2
  $installedVersion = Get-InstalledVersionFromRegistry $RegPath $RegValueName
  if ($null -eq $installedVersion) {
    Write-Step "Step 2 result: Registry version is missing/empty."
  } else {
    Write-Step "Step 2 result: Registry version = '$installedVersion'"
  }

  # Step 3
  Write-Step "Step 3: Comparing website version to registry version"

  if ([string]::IsNullOrWhiteSpace($webInfo.VersionString)) {
    Write-Step "ERROR: Website version string is empty. Exiting with error code 11."
    exit 11
  }

  $installFlag = $false
  if ($null -eq $installedVersion) {
    $installFlag = $true
    Write-Step "Step 3 decision: Registry version missing => InstallFlag = TRUE"
  } elseif ($installedVersion -eq $webInfo.VersionString) {
    $installFlag = $false
    Write-Step "Step 3 decision: Versions match => InstallFlag = FALSE"
  } else {
    $installFlag = $true
    Write-Step "Step 3 decision: Versions differ => InstallFlag = TRUE"
    Write-Step "Website: '$($webInfo.VersionString)'"
    Write-Step "Registry: '$installedVersion'"
  }

  # Step 4
  if (-not $installFlag) {
    Write-Step "Step 4: InstallFlag is FALSE. No action needed. Exiting 0."
    exit 0
  }

  Write-Step "Step 4: InstallFlag is TRUE. Proceeding to download and install."
  Ensure-Directory $TempDir

  $fileName = [System.IO.Path]::GetFileName(([Uri]$webInfo.DownloadUrl).AbsolutePath)
  if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = "MSP_Installer.exe" }
  $installerPath = Join-Path $TempDir $fileName

  Download-File $webInfo.DownloadUrl $installerPath
  $rc = Run-Installer $installerPath

  # Step 5
  if ($rc -ne 0) {
    Write-Step "Step 5: Installer returned non-zero ($rc). Exiting with installer return code."
    exit $rc
  }

  Write-Step "Step 5: Installer returned 0. Updating registry version to '$($webInfo.VersionString)'."
  Set-RegistryVersion $RegPath $RegValueName $webInfo.VersionString

  # Step 6
  Write-Step "Step 6: Completed successfully. Exiting 0."
  exit 0
}
catch {
  Write-Step "FATAL ERROR: $($_.Exception.Message)"
  exit 99
}
