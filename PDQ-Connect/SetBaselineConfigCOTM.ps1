# This routine sets secure baseline registry settings for COTM computers.
# globals
$hive = "HKEY_LOCAL_MACHINE"


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
    $RegistryPath = "$regHive:\$regPath"
    If (-NOT (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }  
    # Now set the value
    if (-NOT (Get-ItemProperty -path $RegistryPath -Name $regValueName)) {
        New-ItemProperty -Path $RegistryPath -Name $regValueName -Value $regValueData -PropertyType DWORD -Force 
    } Else {
        Set-ItemProperty -Path $RegistryPath -Name $regValueName -Value $regValueData
    }


}

# CONFIGURATION -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Fix for Nessus 42873 – SSL Medium Strength Cipher Suites Supported (SWEET32)
$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128"
$valueName = "Enabled"
$valueType = DWORD
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData

$key = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168/168"
$valueName = "Enabled"
$valueData = 0
Set-RegistryValueDWORD -regHive $hive -regPath $key -regValueName $valueName -regValueData $valueData



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





