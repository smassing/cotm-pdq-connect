#Requires -Version 5.1
<#
.SYNOPSIS
Checks real extraction output under the updater's strict mode without installing.
.DESCRIPTION
Tests both the standalone extractor and the embedded updater helper. Requires
the signed Enterprise EXE and enough space for one extracted MSI. Removes only
the uniquely named temporary MSI created by each test.
#>
[CmdletBinding()]
param (
    [string]$InstallerPath = "$env:USERPROFILE\Downloads\Affinity x64.exe"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Update-Affinity.ps1'), [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors -join "`n") }
$helper = $ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $_.Name -eq 'Invoke-AffinityMsiExtraction'
}
if ($null -eq $helper) { throw 'Embedded extraction helper was not found.' }
Invoke-Expression $helper.Extent.Text

foreach ($kind in @('Standalone', 'Embedded')) {
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) ('COTM-extraction-test-' + [guid]::NewGuid().ToString('N') + '.msi')
    try {
        if ($kind -eq 'Standalone') {
            $result = @(& (Join-Path $PSScriptRoot 'Extract-AffinityMsi.ps1') -InstallerPath $InstallerPath -OutputPath $outputPath)
        } else {
            $result = @(Invoke-AffinityMsiExtraction -InstallerPath $InstallerPath -OutputPath $outputPath)
        }
        if ($result.Count -ne 1 -or $null -eq $result[0]) {
            throw "$kind extractor must return exactly one non-null metadata object; received $($result.Count) outputs."
        }
        $package = $result[0]
        if ($package.ProductName -ne 'Affinity' -or $package.Manufacturer -ne 'Canva') {
            throw "Unexpected $kind MSI identity."
        }
        $version = [version]$package.ProductVersion
        if ($version.Major -lt 3 -or $package.MsiPath -ne $outputPath -or
            (Get-Item -LiteralPath $outputPath).Length -ne $package.SizeBytes -or
            (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash -ne $package.SHA256) {
            throw "$kind MSI metadata does not match its output file."
        }
        Write-Host "PASS: $kind extraction returns one metadata object under StrictMode; Affinity $version."
    } finally {
        # Only this test's GUID-named file; never remove source installers.
        if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath }
    }
}
