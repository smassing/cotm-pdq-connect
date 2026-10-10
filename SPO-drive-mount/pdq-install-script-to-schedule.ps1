# Paste into the PDQ Powershell Install step to schedule the SPO-Drive-Mount.ps1 script to run at logon for all users.
$EventSource = 'COTM.OneDriveMount'
$runKey      = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$name        = 'COTM_SPO_Drive_Mount'
$scriptPath  = 'C:\Program Files\COTMScripts\SPO-Drive-Mount.ps1'
$psExe       = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

# Ensure Event Source exists (one-time)
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
}

if (-not (Test-Path $scriptPath)) {
    Write-EventLog -LogName Application -Source $EventSource -EntryType Error -EventId 6100 `
        -Message "HKLM Run install failed: script not found at $scriptPath"
    throw "Script not found: $scriptPath"
}

# Use -NoLogo and -NonInteractive for logon reliability
$cmd = "`"$psExe`" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

New-Item -Path $runKey -Force | Out-Null
New-ItemProperty -Path $runKey -Name $name -Value $cmd -PropertyType String -Force | Out-Null

Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 6101 `
    -Message "Installed HKLM Run entry '$name' => $cmd"
