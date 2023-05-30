[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]$WinGetAppID
)
Write-Host "WinGetAppID is $WinGetAppID"

#get path to winget
Write-Host "Get WinGet Path (if admin context)"
# Includes Workaround for ARM64 (removed X64 and replaces it with a wildcard)
$ResolveWingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }

if ($ResolveWingetPath) {
    #If multiple version, pick last one
    $WingetPath = $ResolveWingetPath[-1].Path
}

Write-Host "WinGet EXE Path: $WingetPath"

#Get Winget Location in User context
$WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($WingetCmd) {
    $Script:Winget = $WingetCmd.Source
}
#Get Winget Location in System context
elseif (Test-Path "$WingetPath\winget.exe") {
    $Script:Winget = "$WingetPath\winget.exe"
}
else {
    Write-Host "Winget not installed or detected !" "Red"
    return $false
}

#Run winget to list apps and accept source agrements (necessary on first run)
& $Winget list --accept-source-agreements -s winget | Out-Null

#Log Winget installed version
$WingetVer = & $Winget --version
Write-Host "Winget Version: $WingetVer"

#run winget command
Write-Host "Start Run Update/Installer"

#capturing existing installations
$InstalledList = & $Winget list -q $WingetAppID --accept-source-agreements -s winget

Write-Host "Query Results:"
#clean up the garbage in the result scaused by the progress bars
$filteredList = $InstalledList | Where-Object {$_.TrimStart()[0] -match "^[a-zA-Z0-9\-\s]+$"}
#output results to PDQ log
$filteredList

#Flatten list
$InstalledList = [system.String]::Join(" ", $InstalledList)

if ($InstalledList.Contains("No installed package found")) {
    #then do an install
    write-Host "Action: Try install of $WinGetAppID"
    $commandResult = & $winget install --id $WinGetAppID --silent --disable-interactivity --accept-source-agreements -s winget
    } else {
    #then do an upgrade
    Write-Host "Action: Try upgrade of $WinGetAppID"
    $commandResult = & $Winget upgrade --id $WinGetAppID --silent --disable-interactivity --accept-source-agreements -s winget
    }

Write-Host "Result:"
#clean up the garbage in the result scaused by the progress bars
$filteredResult = $commandResult | Where-Object {$_.TrimStart()[0] -match "^[a-zA-Z0-9\-\s]+$"}
#output results to PDQ log
$filteredResult

Write-Host "Action Completed: $WinGetAppID"

