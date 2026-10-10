# SPO-Drive-Mount.ps1
# Exits OneDrive, sets HKCU TimerAutoMount=1 (QWORD) under Business1, restarts OneDrive.
# Logs audit events to Windows Application log (Source: $EventSource)
$EventSource = 'COTM.OneDriveMount'
$EventLogName = 'COTM - SPO Drive Mount'

# Event IDs (runtime)
# 1000 Start
# 1100 Stop OneDrive requested
# 1101 Stop OneDrive succeeded
# 1102 Stop OneDrive not running
# 1103 Stop OneDrive timed out
# 1200 Registry path created
# 1201 Registry value set
# 1300 Start OneDrive requested
# 1301 Start OneDrive succeeded
# 1302 OneDrive exe not found
# 1400 Completed successfully
# 1900 Failed (catch-all)

function Write-AuditEvent {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('Information','Warning','Error')] [string] $Level = 'Information',
        [int] $EventId = 1000
    )
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Level -EventId $EventId -Message $Message
    } catch {
        # If event source doesn't exist or write fails, don't break the task.
        # Optional fallback to file (kept minimal; remove if you want *only* Application log).
        $fallback = Join-Path $env:LOCALAPPDATA 'COTM\Logs\SPO-Drive-Mount.log'
        New-Item -ItemType Directory -Path (Split-Path $fallback) -Force | Out-Null
        Add-Content -Path $fallback -Value ("{0} [{1}] ({2}) {3} (EventLog write failed: {4})" -f (Get-Date), $Level, $EventId, $Message, $_.Exception.Message)
    }
}

try {
    $regPath  = 'HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1'
    $regName  = 'TimerAutoMount'
    $regValue = 1

    Write-AuditEvent -Message "Start. User=$env:USERNAME  SID=$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)" -EventId 1000

    # --- Stop OneDrive with timeout/wait ---
    Write-AuditEvent -Message "Stopping OneDrive (request)." -EventId 1100

    $procs = Get-Process OneDrive -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-AuditEvent -Message "OneDrive not running; nothing to stop." -EventId 1102
    } else {
        # Try graceful close first
        foreach ($p in $procs) {
            try { $null = $p.CloseMainWindow() } catch { }
        }

        # Wait for exit up to $StopTimeoutSeconds seconds
        $deadline = (Get-Date).AddSeconds($StopTimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 250
            $still = Get-Process OneDrive -ErrorAction SilentlyContinue
        } while ($still -and (Get-Date) -lt $deadline)

        if ($still) {
            # Force kill
            $still | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            $still2 = Get-Process OneDrive -ErrorAction SilentlyContinue
            if ($still2) {
                Write-AuditEvent -Message "OneDrive stop timed out; process still present after force stop." -Level Warning -EventId 1103
            } else {
                Write-AuditEvent -Message "OneDrive stopped (force)." -EventId 1101
            }
        } else {
            Write-AuditEvent -Message "OneDrive stopped (graceful)." -EventId 1101
        }
    }

    Start-Sleep -Seconds $StartDelaySeconds

    # --- Registry set (HKCU) ---
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-AuditEvent -Message "Created registry path: $regPath" -EventId 1200
    }

    New-ItemProperty -Path $regPath -Name $regName -PropertyType QWord -Value $regValue -Force | Out-Null
    Write-AuditEvent -Message "Set registry value: $regPath\$regName = $regValue (QWORD)" -EventId 1201

    # --- Start OneDrive with fallback exe locations ---
    Write-AuditEvent -Message "Starting OneDrive (request)." -EventId 1300

    $exeCandidates = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )

    $oneDriveExe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $oneDriveExe) {
        Write-AuditEvent -Message ("OneDrive.exe not found in expected paths: " + ($exeCandidates -join '; ')) -Level Error -EventId 1302
        throw "OneDrive.exe not found."
    }

    Start-Process -FilePath $oneDriveExe | Out-Null
    Start-Sleep -Seconds $PostStartWaitSeconds

    # Confirm start (best-effort)
    $started = Get-Process OneDrive -ErrorAction SilentlyContinue
    if ($started) {
        Write-AuditEvent -Message "OneDrive started: $oneDriveExe" -EventId 1301
    } else {
        Write-AuditEvent -Message "OneDrive start was requested, but process not observed after wait." -Level Warning -EventId 1301
    }

    Write-AuditEvent -Message "Completed successfully." -EventId 1400
    exit 0
}
catch {
    Write-AuditEvent -Message ("FAILED: {0}" -f $_.Exception.Message) -Level Error -EventId 1900
    exit 1
}