# This routine sets secure baseline registry settings for COTM computers.
# globals ----------------------------------------------------------------------------------

#  Registry Hive base
$hive = "HKLM"

#  IMPORTANT!!!!!!  Make sure to increment this value or all you hard work is for naught
#  This will only run if ThisBaselineVersion is higher than the previous one.
$ThisBaselineVersion = 2


#function declarations ---------------------------------------------------------------------
# Set-RegistryValue
function Set-RegistryValueDWORD {

    <#
    .SYNOPSIS
        Sets DWORD registry values in HKLM.
    .DESCRIPTION
        Sets DWORD registry values in HKLM.
    .NOTES
        This function works on Windows
    .EXAMPLE
        Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
    #>

    [CmdletBinding()]
    param (
        # This parameter allows you to type a message string
        [Parameter()]
        [string]$regHive,
        [string]$regPath,
        [string]$regValueName,
        [int]$regValueData
    )


    # Create the key if it does not exist
    $RegistryPath = $regHive + ":\" + $regPath
    If (-NOT (Test-Path $RegistryPath)) { 
        New-Item -Path $RegistryPath -Force | Out-Null 
    }

    # Now set the value
    if (-NOT (Get-ItemProperty -path $RegistryPath -Name $regValueName -ErrorAction Ignore)) {
        New-ItemProperty -LiteralPath $RegistryPath -Name $regValueName -Value $regValueData -PropertyType DWORD -Force 
    } Else {
        Set-ItemProperty -LiteralPath $RegistryPath -Name $regValueName -Value $regValueData
    }


}

# Set-RegistryValue
function Get-IsBaselineCurrent {

    <#
    .SYNOPSIS
        See's if the stored Baseline value is equal to this script.
    .DESCRIPTION
        See's if the stored Baseline value is equal to this script.
    .NOTES
        This function works on Windows
    .EXAMPLE
        Get-IsBaselineCurrent -CurrentBaseline $BaselineVersion
    #>

    [CmdletBinding()]
    param (
        # This parameter allows you to type a message string
        [Parameter()]
        [int]$ThisBaseline
    )


    # Create the key if it does not exist
    $RegistryPath = "HKLM:\SOFTWARE\COTM\Baseline\Registry"
    $RegistryValueName = "Version"
    If (-NOT (Test-Path $RegistryPath)) { 
        New-Item -Path $RegistryPath -Force | Out-Null 
    }

    # Now set the value
    if ((Get-ItemProperty -path $RegistryPath -Name $RegistryValueName -ErrorAction Ignore).Version -ge $ThisBaseline) {
         Exit
    } 

}

# CONFIGURATION -----------------------------------------------------------------------------
#test existing baseline to see if we need to run
#test to see the current installed baseline and if it is greater than or equal to this one
Get-IsBaselineCurrent -ThisBaseline $ThisBaselineVersion


# -----------------------------------------------------------------------------
# Disable TLS 1.0, 1.1, Enable 1.2
$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client"
$valueName = "DisabledByDefault"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server"
$valueName = "DisabledByDefault"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client"
$valueName = "DisabledByDefault"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server"
$valueName = "DisabledByDefault"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"
$valueName = "Enabled"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"
$valueName = "DisabledByDefault"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
$valueName = "Enabled"
$valueData = 1
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
$valueName = "DisabledByDefault"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
Write-Host "Disable TLS 1.0, 1.1, Enable 1.2 complete."


# -----------------------------------------------------------------------------
# Speculative Execution Check Exploit remediation
$key = "SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
$valueName = "FeatureSettingsOverrideMask"
$valueData = 3
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
$valueName = "FeatureSettingsOverride"
$valueData = 72
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
Write-Host "Speculative Execution Check Exploit remediation complete."


# -----------------------------------------------------------------------------
# windows remote desktop settings
$key = "SYSTEM\CurrentControlSet\Control\Terminal Server"
$valueName = "fDenyTSConnections"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\Terminal Server"
$valueName = "updateRDStatus"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
Write-Host "Windows remote desktop settings complete"

# -----------------------------------------------------------------------------
# Disable Flash in Adobe Reader DC
$key = "SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown"
$valueName = "bEnableFlash"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
Write-Host "Disable Flash in Adobe Reader DC complete."

# -----------------------------------------------------------------------------
# Fix for Nessus 42873 – SSL Medium Strength Cipher Suites Supported (SWEET32)
# Re-create the ciphers key.
New-Item 'HKLM:SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers' -Force -ErrorAction Ignore | Out-Null
 
# Disable insecure/weak ciphers.
$insecureCiphers = @(
  'RC4 40/128',
  'RC4 56/128',
  'RC4 64/128',
  'RC4 128/128',
  'Triple DES 168',
  'Triple DES 168/168'
)
Foreach ($insecureCipher in $insecureCiphers) {
  $TestRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\' + $insecureCipher
  If (-NOT (Test-Path $TestRegPath)) { 
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers', $true).CreateSubKey($insecureCipher) 
  } else {
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\' + $insecureCipher, $true)
  }
  $key.SetValue('Enabled', 0, 'DWord')
  $key.close()
  Write-Host "Weak cipher $insecureCipher has been disabled."
}
 
# Enable new secure ciphers.
# - RC4: It is recommended to disable RC4, but you may lock out WinXP/IE8 if you enforce this. This is a requirement for FIPS 140-2.
# - 3DES: It is recommended to disable these in near future. This is the last cipher supported by Windows XP.
# - Windows Vista and before 'Triple DES 168' was named 'Triple DES 168/168' per https://support.microsoft.com/en-us/kb/245030
# $secureCiphers = @(
#   'AES 128/128',
#   'AES 256/256'
# )
# Foreach ($secureCipher in $secureCiphers) {
#   $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers', $true).CreateSubKey($secureCipher)
#   New-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$secureCipher" -name 'Enabled' -value '0xffffffff' -PropertyType 'DWord' -Force | Out-Null
#   $key.close()
#   Write-Host "Strong cipher $secureCipher has been enabled."
# }


# -----------------------------------------------------------------------------
# SAVE FOR LAST
# notify the registry updates are completed
# Set the Baseline Version to this file
$key = "SOFTWARE\COTM\Baseline\Registry"
$valueName = "Version"
$valueData = $ThisBaselineVersion
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData
Write-Host "Registry update completed."
Write-Host "Registry baseline updated to " + $ThisBaselineVersion

