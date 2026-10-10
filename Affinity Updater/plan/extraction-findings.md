# Enterprise MSI extraction findings

Checked October 10, 2026.

## Result

`Extract-AffinityMsi.ps1` extracts the embedded MSI without launching the EXE,
opening the Create MSI dialog, or installing anything. It uses Windows resource
APIs; no 7-Zip, Chocolatey, or Python installation is needed on PDQ targets.

The script checks a valid Canva Authenticode signature on the source EXE,
requires exactly one compound-file resource, and opens the result as a Windows
Installer database to confirm its product name, manufacturer, and version.
It refuses to overwrite an existing output. A reported SHA-256 records the
extracted file; it is not an independently published vendor checksum.

## Local verification

- Source: `C:\Users\steve\Downloads\Affinity x64.exe`.
- Signature: Valid; signer `CN=Canva, O=Canva, S=New South Wales, C=AU`.
- Product: Affinity, manufacturer Canva, version `3.3.1.4940`.
- ProductCode: `{88EF18E6-52BB-42D1-9CC2-3DE0D36F78FA}`.
- Extracted size: 671,649,792 bytes.
- SHA-256: `E148598F2DC86ACA7DE39CEB79AB57EE15417FC76C3ABB7BFBE2B93051D1287D`.
- Extraction and MSI database inspection succeeded in PowerShell 7 and Windows
  PowerShell 5.1, producing the same hash.
- The manually created `C:\Test\Affinity.msi` has the same product identity,
  version, and size but a different hash. Its Property table includes
  `INSTALL_DESKTOP_SHORTCUT_PROPERTY=#0`, which is absent from the raw embedded
  MSI. The other Property table entries matched. This is not a full comparison
  of every MSI table or embedded stream.

Steve uninstalled the previous Enterprise installation, then silently installed
the directly extracted MSI from an elevated PowerShell session with `/qn
/norestart INSTALL_DESKTOP_SHORTCUT_PROPERTY="#0"`. The installer returned 0;
`%TEMP%\Affinity-extracted-install.log` confirms installation success for
`3.3.1.4940`. The installed executable at
`C:\Program Files\Affinity\Affinity\Affinity.exe` has both FileVersion and
ProductVersion `3.3.1.4940`.

Steve confirmed that Affinity launches correctly after this installation.
This test used a machine that
previously had Affinity installed, so it does not establish prerequisite behavior
on a clean machine. Subsequent PDQ clean-install and current-version tests are
recorded below; an upgrade from an older release remains to be tested.

## Reproduce extraction

From the Affinity Updater folder (output directory must exist and file must not):

```powershell
.\Extract-AffinityMsi.ps1 `
    -InstallerPath "$env:USERPROFILE\Downloads\Affinity x64.exe" `
    -OutputPath "$env:TEMP\Affinity-extracted.msi"
```

Discovery outputs already created locally:

- `%TEMP%\Affinity-extracted-discovery.msi`
- `%TEMP%\Affinity-extracted-ps51.msi`

To test the directly extracted MSI in an elevated PowerShell session:

```powershell
$msi = Join-Path $env:TEMP 'Affinity-extracted-ps51.msi'
$log = Join-Path $env:TEMP 'Affinity-extracted-install.log'
$arguments = '/i "{0}" /qn /norestart INSTALL_DESKTOP_SHORTCUT_PROPERTY="#0" /L*v "{1}"' -f $msi, $log
$process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
Write-Host "Installer exit code: $($process.ExitCode)"
Write-Host "Installer log: $log"
```

This command installs the MSI. The desktop shortcut property matches the value
in the MSI Steve generated through the dialog. Verify resulting application
behavior as well as the exit code. Testing the same release on this machine
does not demonstrate an upgrade from an older release.

## References

- [Package maintainer's extraction implementation](https://github.com/DennisGaida/chocolatey-packages/blob/master/canva-affinity/tools/Get-EmbeddedMsi.ps1): evidence that the MSI is stored as a resource; our implementation uses Windows APIs rather than their PE parser.
- [Microsoft LoadLibraryEx documentation](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-loadlibraryexw): loading resources as data without executing the EXE.

## Next integration

`Update-Affinity.ps1` now combines the repository's WinGet discovery pattern,
installed executable version detection, signed Enterprise download, embedded
extraction, elevated silent install, and post-install verification. It rechecks
the MSI version against the installed executable before installation because
the rolling download and WinGet metadata may briefly differ.

Live current-version checks and 14 mocked decision/failure scenarios passed in
PowerShell 7 and Windows PowerShell 5.1. PDQ missing/current-version tests have
now passed; the older-version acceptance test in `../README.md` remains pending.

## First PDQ attempt and correction

The first missing-installation test on `cotm-hotel2` successfully located WinGet,
detected version `3.3.1.4940`, downloaded the Enterprise EXE, and verified its
Canva signature. It failed before launching MSI installation with
`The property 'ProductVersion' cannot be found on this object`.

Local reproduction under StrictMode showed three extraction outputs: a null,
the MSI metadata object, and another null. Windows Installer COM `View.Execute`
and `View.Close` emitted the null values. The caller therefore received an array
instead of a single metadata object. Both calls now explicitly discard their
return values in the standalone extractor and embedded updater helper.

`Test-AffinityExtraction.ps1` exercises the real standalone and embedded
extractors under StrictMode, checks that each returns exactly one metadata
object, and compares the metadata against the extracted MSI. It performs no
installation. Steve deployed the corrected script; the subsequent results are
recorded below.

## PDQ clean installation and repeat run

On October 10, 2026, Steve reported that the corrected full updater installed
successfully on a clean machine through PDQ with exit code 0, and that Affinity
launched correctly afterward.

The supplied repeat-run log at 12:08:37 confirms:

- WinGet was located in the x64 Desktop App Installer folder under WindowsApps.
- Available and installed Enterprise versions were both `3.3.1.4940`.
- The script skipped downloading and installing and returned 0.

An in-place upgrade from an older Enterprise release, application launch after
upgrade, and preservation of user settings remain pending. No preliminary
uninstall should be performed for the upgrade test.
