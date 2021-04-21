# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

# Create a tag file just so WS1 knows this was installed
if (-not (Test-Path "$($env:ProgramData)\Airwatch\WS1Branding"))
{
    Mkdir "$($env:ProgramData)\Airwatch\WS1Branding"
}
Set-Content -Path "$($env:ProgramData)\Airwatch\WS1Branding\WS1Branding.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\Airwatch\WS1Branding\WS1Branding.log"

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
$config.Config.RemoveApps.App | % {
	$current = $_
	$apps | ? {$_.DisplayName -eq $current} | % {
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
Get-ChildItem "$($installFolder)LPs" -Filter *.cab | % {
	Write-Host "Adding language pack: $($_.FullName)"
	Add-WindowsPackage -Online -NoRestart -PackagePath $_.FullName
}

# STEP 7: Change language
if ($config.Config.Language) {
	Write-Host "Configuring language using: $($config.Config.Language)"
	& $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$($installFolder)$($config.Config.Language)`""
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
$config.Config.AddFeatures.Feature | % {
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

Stop-Transcript
