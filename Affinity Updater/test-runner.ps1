$process = Start-Process msiexec.exe -ArgumentList `
    '/i "C:\Test\Affinity.msi" /qn /norestart /L*v "C:\Test\Affinity-install.log"' `
    -Wait -PassThru

Write-Host "Installer exit code: $($process.ExitCode)"