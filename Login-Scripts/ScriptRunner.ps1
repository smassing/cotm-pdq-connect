$logonScripts = Get-ChildItem -Path "C:\COTM\Logon\*.ps1" -File

$sortedScripts = $logonScripts | Sort-Object

ForEach ($script in $sortedScripts) {
    
    Try {
        $result = Start-Process -FilePath "powershell.exe" -ArgumentList "-File " + $script -Wait -NoNewWindow -ErrorAction Continue
        Write-Host $result
    } 
    Catch {
        Write-Host "Process run failure: " + $script
    }

}
