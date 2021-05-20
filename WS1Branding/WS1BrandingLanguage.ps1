$WorkingDir = "$($env:ProgramData)\Airwatch\WS1Branding"

# Start logging
Start-Transcript "$WorkingDir\WS1BrandingLanguage.log"

Write-Host "Configuring language using: $WorkingDir\Language.xml"
Write-Host "Command Line : $env:SystemRoot\System32\control.exe intl.cpl,,/f:$WorkingDir\Language.xml"
#& $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$WorkingDir\Language.xml`""
Start-Process -Filepath "$env:SystemRoot\System32\control.exe" -ArgumentList "intl.cpl,,/f:`"$WorkingDir\Language.xml`"" -Wait

# Remove the scheduled task
Disable-ScheduledTask -TaskName "WS1BrandingLanguage" -ErrorAction Ignore
Unregister-ScheduledTask -TaskName "WS1BrandingLanguage" -Confirm:$false -ErrorAction Ignore
Write-Host "Scheduled task unregistered."

#Initiating the restart
Write-Host "Initiating a restart Now !"
Stop-Transcript
& shutdown.exe /r /t 0 /f

