[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]$KBArticleID
)
Write-Host "KBArticleID is $KBArticleID"

$Module = "PSWindowsUpdate"
$RegPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"

IF(Get-Module -ListAvailable -Name $Module){
    Write-Host "$Module module is Installed."
}
ELSE{
    Write-Host "$Module module is Not Installed."
    Write-Host "Installing NuGet Package Installer..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -confirm:$False
    Write-Host "Installing $Module Module..."
    Install-Module -Name $Module -Force -Confirm:$False
}

IF(Test-Path $RegPath){
    Write-Host "$RegPath Exists."
    Write-Host "Removing Old Windows Update registry entries..."
    Stop-Service -Name wuauserv
    Remove-Item $RegPath -Recurse
    Start-Service -name wuauserv
	Write-Host "Windows Update registry entries clean."
}
ELSE{
    Write-Host "Windows Update registry entries clean."
}

Write-Host "Importing $Module Module into PowerShell session..."
Import-Module $Module

Write-Host "Retrieving Available Microsoft Updates..."
Get-WindowsUpdate -MicrosoftUpdate -Verbose

Write-Host "Installing Selected Updates..."
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose -IgnoreReboot -KBArticleID $KBArticleID
