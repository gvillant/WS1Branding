# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

$WorkingDir = "$($env:ProgramData)\Airwatch\WS1Branding"

# Create a tag file just so WS1 knows this was installed
if (-not (Test-Path $WorkingDir))
{
    Mkdir $WorkingDir
}
Set-Content -Path "$WorkingDir\WS1Branding.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$WorkingDir\WS1Branding.log"

# PREP: Load the Config.xml
$installFolder = "$PSScriptRoot\"
Write-Host "Install folder: $installFolder"
Write-Host "Loading configuration: $($installFolder)Config.xml"
[Xml]$config = Get-Content "$($installFolder)Config.xml"

# STEP 1: Apply custom start menu layout
if ($config.Config.CustomLayout) {
	Write-Host "Importing layout using: $($installFolder)$($config.Config.CustomLayout)"
	Copy-Item "$($installFolder)$($config.Config.CustomLayout)" "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" -Force
} 
else {
	Write-Host "CustomLayout config item does not exist"
}

# STEP 2: Set time zone (if specified)
if ($config.Config.TimeZone) {
	Write-Host "Setting time zone: $($config.Config.TimeZone)"
	Set-Timezone -Id $config.Config.TimeZone
}
else {
	# Enable location services so the time zone will be set automatically (even when skipping the privacy page in OOBE) when an administrator signs in
	Write-Host "Enable location services so the time zone will be set automatically"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type "String" -Value "Allow" -Force
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type "DWord" -Value 1 -Force
	Start-Service -Name "lfsvc" -ErrorAction SilentlyContinue
}

# STEP 3: Remove specified provisioned apps if they exist
Write-Host "Removing specified in-box provisioned apps"
$apps = Get-AppxProvisionedPackage -online
$config.Config.RemoveApps.App | ForEach-Object {
	$current = $_
	$apps | Where-Object {$_.DisplayName -eq $current} | ForEach-Object {
		Write-Host "Removing provisioned app: $current"
		$_ | Remove-AppxProvisionedPackage -Online | Out-Null
	}
}

# STEP 4: Install OneDrive per machine
if ($config.Config.OneDriveSetup) {
	Write-Host "Downloading OneDriveSetup"
	$dest = "$($env:TEMP)\OneDriveSetup.exe"
	$client = new-object System.Net.WebClient
	$client.DownloadFile($config.Config.OneDriveSetup, $dest)
	Write-Host "Installing: $dest"
	$proc = Start-Process $dest -ArgumentList "/allusers" -WindowStyle Hidden -PassThru
	$proc.WaitForExit()
	Write-Host "OneDriveSetup exit code: $($proc.ExitCode)"
}
else {
	Write-Host "OneDriveSetup config item does not exist"
}

# STEP 5: Don't let Edge create a desktop shortcut (roams to OneDrive, creates mess)
Write-Host "Turning off (old) Edge desktop shortcut"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v DisableEdgeDesktopShortcutCreation /t REG_DWORD /d 1 /f /reg:64 | Out-Host

# STEP 6: Add language packs
Get-ChildItem "$($installFolder)LPs" -Filter *.cab | ForEach-Object {
	Write-Host "Adding language pack: $($_.FullName)"
	Add-WindowsPackage -Online -NoRestart -PackagePath $_.FullName
}

# STEP 7: Set language and regional settings.
# With WS1 Dropship online, language settings should be applied after the provisioning step because of sysprep resealing. So we will use a scheduled task to apply the xml and reboot the device before the first user logon.  
if ($config.Config.Language) {
	Write-Host "Configuring language using: $($config.Config.Language)"
	Write-Host "Command Line : $env:SystemRoot\System32\control.exe intl.cpl,,/f:$($installFolder)$($config.Config.Language)"
	& $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$($installFolder)$($config.Config.Language)`""

    # Check to see if already scheduled
    $existingTask = Get-ScheduledTask -TaskName "WS1BrandingLanguage" -ErrorAction SilentlyContinue
    if ($existingTask -ne $null)
    {
        Write-Host "Scheduled task already exists."
    }
	else { 
    	# Copy WS1BrandingLanguage script and xml to $WorkingDir
		Copy-Item "$PSScriptRoot\WS1BrandingLanguage.ps1" "$WorkingDir\WS1BrandingLanguage.ps1" -Force
		Copy-Item "$PSScriptRoot\$($config.Config.Language)" "$WorkingDir\Language.xml" -Force

		# Create the scheduled task action
		$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy bypass -WindowStyle Hidden -File $WorkingDir\WS1BrandingLanguage.ps1"

		# Create the scheduled task trigger
		$triggers = @()
		$triggers += New-ScheduledTaskTrigger -AtStartup
		
		# Register the scheduled task
		Register-ScheduledTask -User SYSTEM -Action $action -Trigger $triggers -TaskName "WS1BrandingLanguage" -Description "WS1BrandingLanguage" -Force
		Write-Host "Scheduled task created."
	}
}
else {
	Write-Host "Language config item does not exist"
	}

# STEP 8: Add features on demand ONLINE
	$currentWU = (Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ErrorAction Ignore).UseWuServer
	if ($currentWU -eq 1)
	{
		Write-Host "Turning off WSUS"
		Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 0
		Restart-Service wuauserv
	}
	$config.Config.AddFeatures.Feature | ForEach-Object {
		Write-Host "Adding Windows feature: $_"
		Add-WindowsCapability -Online -Name $_
	}
	if ($currentWU -eq 1)
	{
		Write-Host "Turning on WSUS"
		Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 1
		Restart-Service wuauserv
}

# STEP 9: Customize default apps
if ($config.Config.DefaultApps) {
	Write-Host "Setting default apps: $($config.Config.DefaultApps)"
	& Dism.exe /Online /Import-DefaultAppAssociations:`"$($installFolder)$($config.Config.DefaultApps)`"
}
else {
	Write-Host "DefaultApps config item does not exist"
}

# STEP 10: Set registered user and organization
if ($config.Config.RegisteredOwner) {
	Write-Host "Configuring RegisteredOwner information: $($config.Config.RegisteredOwner)"
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v RegisteredOwner /t REG_SZ /d "$($config.Config.RegisteredOwner)" /f /reg:64 | Out-Host
}
else {
	Write-Host "RegisteredOwner config item does not exist"
}

if ($config.Config.RegisteredOrganization) {	
	Write-Host "Configuring RegisteredOrganization information: $($config.Config.RegisteredOrganization)"
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v RegisteredOrganization /t REG_SZ /d "$($config.Config.RegisteredOrganization)" /f /reg:64 | Out-Host
}
else {
	Write-Host "RegisteredOrganization config item does not exist"
}

# STEP 11: Configure OEM branding info
if ($config.Config.OEMInfo)
{
	Write-Host "Configuring OEM branding info"

	$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
	Write-Host "Manufacturer: $Manufacturer"
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Manufacturer /t REG_SZ /d "$Manufacturer" /f /reg:64 | Out-Host
	
	$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
	Write-Host "Model: $Model"
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Model /t REG_SZ /d "$Model" /f /reg:64 | Out-Host
	
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportPhone /t REG_SZ /d "$($config.Config.OEMInfo.SupportPhone)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportHours /t REG_SZ /d "$($config.Config.OEMInfo.SupportHours)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportURL /t REG_SZ /d "$($config.Config.OEMInfo.SupportURL)" /f /reg:64 | Out-Host
	Copy-Item "$installFolder\$($config.Config.OEMInfo.Logo)" "C:\Windows\$($config.Config.OEMInfo.Logo)" -Force
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Logo /t REG_SZ /d "C:\Windows\$($config.Config.OEMInfo.Logo)" /f /reg:64 | Out-Host
}
else {
	Write-Host "OEMInfo config item does not exist"
}

# STEP 12: Disable network location fly-out
Write-Host "Turning off network location fly-out"
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /f

# STEP 13: Disable new Edge desktop icon
Write-Host "Turning off Edge desktop icon"
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "CreateDesktopShortcutDefault" /t REG_DWORD /d 0 /f /reg:64 | Out-Host

# STEP 14: Update OS 
if ($($config.Config.UpdateOS) -eq "True") 
{
	# Main logic
	$needReboot = $false
	Write-Host "UpdateOS config item is set to: $($config.Config.UpdateOS) then installing updates ..."

	# Load module from PowerShell Gallery
	$null = Install-PackageProvider -Name NuGet -Force
	$null = Install-Module PSWindowsUpdate -Force
	Import-Module PSWindowsUpdate

	# Install all available updates
	Get-WindowsUpdate -Install -IgnoreUserInput -AcceptAll -WindowsUpdate -IgnoreReboot | Select-Object Title, KB, Result | Format-Table
	$needReboot = (Get-WURebootStatus -Silent).RebootRequired

	# Check return code
	if ($needReboot)
	{
		Write-Host "Windows Update indicated that a reboot is needed."
	}
	else
	{
		Write-Host "Windows Update indicated that no reboot is required."
	}

	# For whatever reason, the reboot needed flag is not always being properly set.  So we always want to force a reboot.
		Write-Host "Exiting with return code 3010 to indicate a soft reboot is needed."
		Stop-Transcript
		Exit 3010
}
else {
	Write-Host "UpdateOS config item is set to: $($config.Config.UpdateOS)"
}
Stop-Transcript
