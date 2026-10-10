I have that workflow for another app, Ministry Scheduler Pro.  I am scraping a releases page on their website for version changes, if the version matches a regostry value I have set previously, is exits, if it is higher it downloads and installs the app silently.
Yes. That same pattern is a good fit for Affinity.

In fact, because WinGet already gives you a structured current-version source for Canva.Affinity, I would prefer that over scraping an Affinity release page. You could use WinGet only as your version oracle, while continuing to install the Enterprise build yourself.

Conceptually:

Query WinGet for latest Canva.Affinity version
              ↓
Read your registry value
HKLM\...\Affinity\ManagedVersion
              ↓
        Versions equal?
          ↙       ↘
        Yes        No
        Exit        ↓
             Get Enterprise EXE
                    ↓
             Verify signature
                    ↓
             Silent install
                    ↓
          Verify installed version
                    ↓
          Update registry value
That is essentially your Ministry Scheduler Pro workflow with one improvement: you don't have to scrape HTML to determine whether a release occurred.

The remaining problem is the Enterprise download URL. That's now the thing worth reverse-engineering rather than the release/version detection. We need to determine whether the current Affinity site has either:

A stable Enterprise download URL that redirects to the latest build.
A JSON/API call behind its Download button.
A predictable version-specific URL.
A bootstrapper that always retrieves the latest Enterprise package.
If any of those exists, your existing architecture should translate almost directly to Affinity.

I'd also add one safeguard to your existing pattern for Affinity: after downloading the EXE, validate that its Authenticode signature is valid and from the expected publisher before executing it:

$signature = Get-AuthenticodeSignature $Installer

if ($signature.Status -ne 'Valid') {
    throw "Affinity installer does not have a valid digital signature."
}

We could also check the signer identity so that a compromised/changed download isn't blindly executed.

I think the next investigation should focus entirely on that Enterprise download mechanism. If we can identify a stable way to retrieve the current Enterprise EXE, you've basically already got the rest of the solution.

Thatmay be the biggest issue.  Right now I have to sign in with my email, recieve a code then enter that to get to a download page.  let me see if that download page is just a hodden link or if I need it each time, I will paste it in another browser
That is exactly the test I would do.

The public Affinity page confirms that the download workflow intentionally requires Canva sign-in, and that Enterprise (Intel/AMD) is a distinct installer option. 

Paste the actual Enterprise installer download link into an incognito/private browser where you are not authenticated. There are three useful outcomes:

It downloads immediately: excellent. We may have a stable or sufficiently reusable URL that PowerShell can call directly.
It redirects to login: the server is enforcing authentication, so we'll need another approach.
It fails after some time: it's probably a signed/expiring URL (SAS-style token, presigned URL, etc.). In that case, inspect the URL for parameters such as expires, signature, token, X-Amz-*, or similar.
There's another possibility that would be especially useful: the authenticated page might obtain the installer URL from a JSON/API endpoint. If so, authentication might only protect the page that reveals the URL while the actual Enterprise binary is publicly accessible.

Once you get to that page, send me either the download-page URL or the Enterprise download-link URL. I can inspect its structure and see whether we can derive a stable endpoint.

And I wouldn't be too discouraged by the login yet. Affinity publicly says the Enterprise installer is specifically the recommended installer for business Windows devices, so there ought to be some reasonable mechanism for organizations to redistribute/deploy that binary. 

It appears to be simply obfuscated so they can show some instructions:  The url is https://downloads.affinity.studio/Affinity%20x64.exe

Yes. That changes the picture substantially. The URL appears to be a public, unauthenticated, rolling “latest Enterprise installer” URL:

Affinity Enterprise x64 installer

I found independent confirmation from the current Chocolatey package for Canva Affinity. Its automation uses that exact URL, and its package comments explicitly state that the URL is not version-locked and always serves the current build. 

That is nearly ideal for your PDQ workflow.

I think we have all the pieces
Your Affinity updater could work very similarly to Ministry Scheduler Pro:

1. Determine latest available version
        ↓
2. Read your stored registry version
        ↓
3. Same or newer?
      YES → Exit
       NO
        ↓
4. Download:
   https://downloads.affinity.studio/Affinity%20x64.exe
        ↓
5. Validate Authenticode signature
        ↓
6. Determine downloaded installer version
        ↓
7. Confirm it is actually newer
        ↓
8. Silently install Enterprise Affinity
        ↓
9. Verify C:\Program Files\Affinity\Affinity\Affinity.exe
        ↓
10. Write successfully installed version to registry
There's an additional useful discovery: the Enterprise EXE contains an MSI. The Chocolatey maintainers are extracting that embedded MSI and installing it silently. Their package identifies the normal installed executable as:

C:\Program Files\Affinity\Affinity\Affinity.exe
and reads FileVersionRaw from it to determine the installed version. 

So you might not even need your own registry value as the authoritative installed version. You could query:

$AffinityExe = "$env:ProgramFiles\Affinity\Affinity\Affinity.exe"

if (Test-Path $AffinityExe) {
    [Version]$InstalledVersion =
        (Get-Item $AffinityExe).VersionInfo.FileVersionRaw
}

I'd still consider retaining your registry value for tracking what your updater last successfully deployed, but the executable itself gives us independent verification.

One improvement over your MSP script
Because this URL always returns whatever Affinity considers current, don't trust the URL/version relationship.

Download first to a temporary location, then validate what you actually received:

$Installer = "$env:TEMP\Affinity-x64.exe"
$Url = "https://downloads.affinity.studio/Affinity%20x64.exe"

Invoke-WebRequest -Uri $Url -OutFile $Installer

# Verify digital signature
$Signature = Get-AuthenticodeSignature $Installer

if ($Signature.Status -ne "Valid") {
    throw "Downloaded Affinity installer has an invalid Authenticode signature."
}

# Inspect downloaded file
$File = Get-Item $Installer

Write-Host "Downloaded: $($File.Name)"
Write-Host "Version:    $($File.VersionInfo.FileVersion)"
Write-Host "Publisher:  $($Signature.SignerCertificate.Subject)"

Then compare the downloaded version against the installed version before executing anything.

That actually raises an interesting possibility: we may not need WinGet at all.

If a HEAD request against the rolling URL exposes useful metadata such as Last-Modified, ETag, or Content-Length, your PDQ script could cheaply determine whether the installer has changed before downloading ~600 MB. If it has changed, download it, validate the signature, extract its version, compare it against the installed version, and install only when appropriate.

I'll check whether downloads.affinity.studio exposes useful HTTP headers for that URL next. If it does, this could become a particularly clean self-maintaining PDQ package.

Go ahead and check
I checked. The main conclusion is solid, although I couldn't directly retrieve the CDN's HEAD response through the browsing environment.

The Enterprise URL is definitely a rolling/latest installer URL:

Affinity Enterprise x64 installer

The current Chocolatey package uses that exact URL and explicitly notes that it is not version-locked and always serves the current build. Their automation downloads it and recalculates the SHA-256 whenever a new Affinity version is packaged. 

I would test the headers from PowerShell
On one of your machines, run:

$Url = "https://downloads.affinity.studio/Affinity%20x64.exe"

$response = Invoke-WebRequest `
    -Uri $Url `
    -Method Head `
    -UseBasicParsing

$response.Headers | Format-List

We're particularly interested in:

ETag
Last-Modified
Content-Length
If Affinity provides ETag, that's ideal. Your updater could store that rather than downloading ~630 MB every time it runs. The current installer is roughly 630 MB. 

For example:

$Url = "https://downloads.affinity.studio/Affinity%20x64.exe"

$response = Invoke-WebRequest `
    -Uri $Url `
    -Method Head `
    -UseBasicParsing

$ETag = $response.Headers["ETag"]
$LastModified = $response.Headers["Last-Modified"]
$ContentLength = $response.Headers["Content-Length"]

Write-Host "ETag:         $ETag"
Write-Host "Last Modified: $LastModified"
Write-Host "Size:          $ContentLength"

There's an even better fallback
Even if the CDN doesn't provide useful ETag/Last-Modified data, I don't think we need to download the Enterprise installer just to discover the version.

Use WinGet for version detection:

winget show --id Canva.Affinity --exact

Then compare that version against:

$AffinityExe = "$env:ProgramFiles\Affinity\Affinity\Affinity.exe"

$InstalledVersion =
    (Get-Item $AffinityExe).VersionInfo.FileVersionRaw

Only download the Enterprise EXE if:

WinGet version > installed Enterprise version
That's potentially the cleanest architecture because the 630 MB download occurs only when Affinity actually releases an update.

And we have independent confirmation that the Enterprise installer ends up installing:

C:\Program Files\Affinity\Affinity\Affinity.exe
The Chocolatey automation is already using that executable's FileVersionRaw for installed-version detection. 

So I think your updater is shaping up as:

winget show Canva.Affinity
        │
        ▼
 Get latest version
        │
        ▼
C:\Program Files\Affinity\
 Affinity\Affinity.exe
        │
        ▼
Compare FileVersionRaw
        │
   ┌────┴────┐
   │         │
 Same      Newer
   │         │
 Exit        ▼
        Download rolling
        Enterprise EXE
             │
             ▼
       Verify signature
             │
             ▼
       Silent install
             │
             ▼
       Verify version
That is actually cleaner than scraping the Affinity website, and you don't need your custom registry version value unless you want it for deployment auditing.

Run that HEAD snippet and paste the headers here. If it gives us a usable ETag, there's another option where we can eliminate WinGet from the process entirely.

The actuall porcess should if "same" then exit if "not exist" or "newer" the install
Correct. More precisely, the decision logic should be based on the installed Enterprise version, with three outcomes:

Get latest Affinity version
          │
          ▼
Does Affinity Enterprise exist?
       /        \
     NO          YES
      │           │
      │      Get installed version
      │           │
      │           ▼
      │     Compare versions
      │       /       \
      │    SAME       OLDER
      │      │          │
      │     EXIT        │
      │                 │
      └────────┬────────┘
               ▼
     Download Enterprise EXE
               │
               ▼
       Verify signature
               │
               ▼
        Silent install
               │
               ▼
     Verify installed version
And in PowerShell terms, roughly:

if (-not (Test-Path $AffinityExe)) {
    # Not installed
    $InstallNeeded = $true
}
else {
    [Version]$InstalledVersion =
        (Get-Item $AffinityExe).VersionInfo.FileVersionRaw

    if ($InstalledVersion -lt $LatestVersion) {
        # Installed version is older
        $InstallNeeded = $true
    }
    else {
        # Same version OR somehow newer than published version
        $InstallNeeded = $false
    }
}

if (-not $InstallNeeded) {
    Write-Host "Affinity is current. Exiting."
    exit 0
}

# Download, validate, and install current Enterprise release

I'd actually use InstalledVersion -lt LatestVersion rather than simply -ne. That protects you if a workstation somehow has a newer build than the version WinGet currently reports. We don't want the script inadvertently downgrading it.

So the rule becomes:

Missing → install
Older → upgrade
Same → exit
Newer → exit and probably log a warning

That's the logic I'd build into the final PDQ Connect script.

looks good.  We will come back to this.  Thanks.
Sounds good. We’ve got a solid path for the Affinity Enterprise updater when you’re ready to build it.

