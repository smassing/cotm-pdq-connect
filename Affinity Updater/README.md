# Affinity updater for Christ on the Mountain

`Update-Affinity.ps1` is a standalone PDQ PowerShell script. The extraction
helper is embedded; targets do not need the other repository files or 7-Zip.

## PDQ setup

1. Add a PowerShell step and paste the complete contents of `Update-Affinity.ps1`
   into it, or deploy and run that file.
2. Run as SYSTEM or an elevated administrator using 64-bit PowerShell on x64
   Windows. Windows PowerShell 5.1 and PowerShell 7 are supported. Full Language
   mode is required for the embedded resource reader.
3. Allow enough time for a roughly 650 MB download, extraction, and installation.
   Start with a 30-minute deployment timeout. Allow several GB of free disk space.
4. Configure success codes `0` and `3010` where PDQ supports them. Code `3010`
   means installation was verified but Windows reports a reboot is required.
   The script does not initiate a reboot.
5. Test against the machines listed below before scheduling wider deployment.

WinGet must be available to the PDQ account, and its `winget` source must contain
`Canva.Affinity`. The updater uses the existing repository pattern for locating
WinGet through PATH or the newest x64 Desktop App Installer folder. It queries
numeric version rows with `winget show --versions` rather than installing the
WinGet/MSIX package or parsing localized status messages.

The target account needs network access to the WinGet source, the Affinity
download URL and any CDN redirects, and certificate validation services.

## Commands

Run from the Affinity Updater folder. The normal command requires elevation
when installation is needed:

```powershell
.\Update-Affinity.ps1
```

Query versions without downloading or installing:

```powershell
.\Update-Affinity.ps1 -CheckOnly
```

Keep the downloaded EXE and extracted MSI after a successful installation:

```powershell
.\Update-Affinity.ps1 -KeepInstaller
```

When running as a file, use a dedicated PowerShell process; the script sets its
process exit code with `exit`.

## Behavior

| Installed Enterprise version | Action |
| --- | --- |
| Missing | Download and install |
| Older than WinGet | Download and upgrade in place |
| Equal to WinGet | Exit 0 without downloading |
| Newer than WinGet | Exit 0 without downloading or downgrading |

The installed version comes from
`C:\Program Files\Affinity\Affinity\Affinity.exe`. An existing but unreadable or
unrecognized executable is an error, not an assumed missing installation.
The script manages Affinity 3+ Enterprise x64 at its default install path;
custom paths, ARM64, legacy V2 apps, and MSIX migrations are outside this script's
scope. An MSIX installation alone is not detected as Enterprise and may coexist
with a newly installed Enterprise copy.

Before installation, the script:

- Confirms the source EXE has a valid signature from Canva.
- Extracts the MSI without launching the EXE and verifies its product identity.
- Refuses a downloaded package older than the queried WinGet version.
- Uses a newer signed Enterprise release if the rolling download is ahead of
  WinGet, and rechecks the installed version to prevent downgrades.
- Refuses installation while an `Affinity` process is running; close the app
  and retry. It does not terminate users' processes.

The MSI command uses `/qn /norestart INSTALL_DESKTOP_SHORTCUT_PROPERTY="#0"`.
Other runtime settings retain the embedded MSI defaults. There is no preliminary
uninstall, registry version marker, or automatic prerequisite installation.
After MSI exit 0 or 3010, the executable version must be at least the extracted
MSI version. A mismatch fails the deployment, including if a reboot may be
needed to complete the change; inspect the log before retrying.

## Logs and troubleshooting

PDQ captures console output for every run. Installation attempts additionally
save `updater.log` and `msi-install.log` under:

```text
C:\ProgramData\COTM\AffinityUpdater\<unique-run-id>\
```

The run path appears in the console output. Each staging directory permits
access only to SYSTEM and administrators. Downloaded payloads are deleted after
success unless `-KeepInstaller` is used. Failures retain staged files. Logs are
retained; review and remove older troubleshooting directories as needed.
Exit 1 indicates a failure; examine the PDQ output and MSI log.

## Validation

The standalone script passed live current-version checks in PowerShell 7 and
Windows PowerShell 5.1: both detected installed/latest `3.3.1.4940` and skipped
download/installation. `Test-UpdateAffinity.ps1` passed 14 mocked scenarios in
both hosts, including missing/current/newer versions, upgrades, stale downloads,
installer validation failure, MSI failure, verification mismatch, and reboot
handling. These tests do not perform real installs.

The embedded extraction approach has been tested locally, and Steve successfully
installed and launched its extracted MSI. See `plan/extraction-findings.md`.
Steve subsequently confirmed that the corrected full updater installed on a
clean machine through PDQ with exit code 0 and that Affinity launched correctly.
The supplied repeat-run log confirms installed/latest `3.3.1.4940`, exit 0, and
no download or installation. An upgrade from an older release remains pending.

PDQ acceptance tests:

- Missing Enterprise: install and launch; check prerequisite behavior on a
  machine that has not previously run Affinity.
- Older Enterprise: record its initial version, upgrade without uninstalling,
  verify the new executable version, launch, and confirm user settings remain.
- Current Enterprise: exit 0 with no download or installation.
- Run the updater again after a successful install/upgrade: exit 0 without
  downloading.

For repeatable decision tests (no downloads or installs):

```powershell
.\Test-UpdateAffinity.ps1
```

For real extraction and metadata regression checks under StrictMode:

```powershell
.\Test-AffinityExtraction.ps1 -InstallerPath "$env:USERPROFILE\Downloads\Affinity x64.exe"
```

This tests both extractor copies, checks that each returns only its metadata
object, and verifies output size and SHA-256. It does not install anything and
removes its own temporary MSI files. This check covers the COM output behavior
that caused the first PDQ attempt to fail before installation.
