#Requires -Version 5.1
# Decision/exit-code tests with download, extraction, installation, and logging
# mocked. No packages are downloaded, installed, or removed by this test script.
$ErrorActionPreference = 'Stop'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Update-Affinity.ps1'), [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors -join "`n") }
# Load function declarations only, never the updater's top-level exit/invocation.
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) {
        Invoke-Expression $node.Extent.Text
    }
}
function Write-AffinityLog { param($Message) }
function Assert-AffinityAdministrator {}
function Assert-AffinityClosed {}
function New-AffinityRunDirectory { return 'C:\MockAffinityRun' }
function Start-Transcript { param($Path) }
function Stop-Transcript {}
function Get-AffinityLatestVersion {
    if ($script:QueryFails) { throw 'Simulated WinGet failure' }
    return [version]'3.3.1.4940'
}
function Get-AffinityInstalledVersion {
    $i = [Math]::Min($script:Reads, $script:Installed.Count - 1)
    $script:Reads++
    return $script:Installed[$i]
}
function Receive-AffinityInstaller { param($Path) $script:Downloads++ }
function Invoke-AffinityMsiExtraction {
    param($InstallerPath, $OutputPath)
    if ($script:ExtractionFails) { throw 'Simulated invalid signature or MSI' }
    return [pscustomobject]@{ProductVersion=$script:Target;SHA256='TEST'}
}
function Start-AffinityMsi {
    param($MsiPath, $LogPath)
    $script:Installs++
    return $script:MsiCode
}
function Test-Scenario {
    param($Name, $Versions, $Target='3.3.1.4940', $MsiCode=0,
        $ExpectedCode=0, $ExpectedDownloads=0, $ExpectedInstalls=0,
        [switch]$CheckOnly, [switch]$QueryFails, [switch]$ExtractionFails)
    $script:Installed = $Versions
    $script:Target = $Target
    $script:MsiCode = $MsiCode
    $script:QueryFails = [bool]$QueryFails
    $script:ExtractionFails = [bool]$ExtractionFails
    $script:Reads = $script:Downloads = $script:Installs = 0
    $script:DownloadUrl = 'https://example.invalid/not-used'
    $code = Invoke-AffinityUpdate -OnlyCheck:$CheckOnly -RetainInstaller
    if ($code -ne $ExpectedCode -or $script:Downloads -ne $ExpectedDownloads -or $script:Installs -ne $ExpectedInstalls) {
        throw "$Name failed: exit=$code, downloads=$script:Downloads, installs=$script:Installs"
    }
    Write-Host "PASS: $Name"
}
$current = [version]'3.3.1.4940'
$older = [version]'3.2.3.4646'
$newer = [version]'3.4.0.5000'
Test-Scenario 'Current: no download' -Versions @($current)
Test-Scenario 'Newer: no downgrade' -Versions @($newer)
Test-Scenario 'Missing: check only' -Versions @($null) -CheckOnly
Test-Scenario 'Older: check only' -Versions @($older) -CheckOnly
Test-Scenario 'WinGet failure: no download' -Versions @($older) -QueryFails -ExpectedCode 1
Test-Scenario 'Missing: install and verify' -Versions @($null,$null,$current) -ExpectedDownloads 1 -ExpectedInstalls 1
Test-Scenario 'Older: upgrade and verify' -Versions @($older,$older,$current) -ExpectedDownloads 1 -ExpectedInstalls 1
Test-Scenario 'Stale Enterprise download: refuse installation' -Versions @($older) -Target '3.3.0.4850' -ExpectedCode 1 -ExpectedDownloads 1
Test-Scenario 'Invalid installer: refuse installation' -Versions @($older) -ExtractionFails -ExpectedCode 1 -ExpectedDownloads 1
Test-Scenario 'Changed during download: skip installation' -Versions @($older,$newer) -ExpectedDownloads 1
Test-Scenario 'Enterprise ahead of WinGet: verify actual release' -Versions @($older,$older,$newer) -Target '3.4.0.5000' -ExpectedDownloads 1 -ExpectedInstalls 1
Test-Scenario 'MSI failure: propagate failure' -Versions @($older) -MsiCode 1603 -ExpectedCode 1 -ExpectedDownloads 1 -ExpectedInstalls 1
Test-Scenario 'Verification mismatch: fail' -Versions @($older) -ExpectedCode 1 -ExpectedDownloads 1 -ExpectedInstalls 1
Test-Scenario 'Reboot required: return 3010' -Versions @($older,$older,$current) -MsiCode 3010 -ExpectedCode 3010 -ExpectedDownloads 1 -ExpectedInstalls 1
Write-Host 'All 14 scenarios passed without installing software.'
