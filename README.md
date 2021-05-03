# WS1Branding
This repository contains a sample PowerShell script that can be packaged into a WS1 app to customize Windows 10 devices.
Forked from the script developped initially by Michael Niehaus for MS Intune https://github.com/mtniehaus/AutopilotBranding

# Capabilities
These customizations are currently supported:

- Customize start menu layout. By default it will apply a simple two-icon layout (similiar to the default one on Windows 10 1903, but without the Office app).
- Set time zone. The time zone will be set to the specified time zone name (Pacific Standard Time by default). If time zone is not specified, then location services will be enabled to setup the timezone automatically
- Remove in-box provisioned apps. A list of in-box provisioned apps will be removed.
- Install updated OneDrive client per-machine. To support the latest OneDrive features, the client will be updated and installed per-machine (instead of the per-user default).
- Disable the Edge desktop icon. When using OneDrive Known Folder Move, this can cause duplicate (and unnecessary) shortcuts to be synced.
- Install language packs. You can embed language pack CAB files (place them into the LPs folder), and each will be automatically installed. (In a perfect world, these would be pulled from Windows Update, but there's no simple way to do that, hence the need to include these in the ZIP. You can download the language pack ISO from MSDN or VLSC.)
- Install features on demand (FOD). Specify a list of features that you want to install, from the list at https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod. The needed components will be downloaded from Windows Update automatically and added to the running OS.
- Configure language settings. Adding a language pack isn't enough - you have to tell Windows that you want it to be configured for all users. This is done through an XML file fed to INTL.CPL; customize the file as needed. (Note this is commented out by default in the Config.xml file.)
- Configure default apps. Import a list of file associations (as created by manually configuring the associations that you want and then using "DISM /Online /Export-DefaultAppAssociations:C:\Associations.xml" to export those settings) that should replace the default app associations. (Note that even though an example is included from a customized Windows 10 1903 image, making IE 11 the default browser, you should replace this file with your own exported version. Also, do not edit the file that you exported, e.g. to remove entries that you didn't change.)
- Configure the "OEM" support information, you can check on settings/about
- Rename Computer: Only for AD On-Prem scenario, the script will rename the computer as soon as it is able to communicate with AD domain controlers. Please follow the requirements explained here : https://oofhours.com/2020/05/19/renaming-autopilot-deployed-hybrid-azure-ad-join-devices/
- REMOVED : Configure background image. A custom theme is deployed with a background image; the default user profile is then configured to use this theme. (Note that this won't work if the user is enabled for Enterprise State Roaming and has previously configured a background image.)

# Using
setup the config.xml file and other required files, accordingly to the customizations you decided to implement : associations.xml, Language.xml, Layout.xml, Dell .bmp ...  

# Requirements and Dependencies
for renaming AD objects, check requirements here : https://oofhours.com/2020/05/19/renaming-autopilot-deployed-hybrid-azure-ad-join-devices/

# Building
Zip the folder (without "extra" root folder, ie the ps1 file script should be at the higher level) then create a WS1 application with following settings:
- Install as device
- Cmdline = powershell.exe -noprofile -executionpolicy bypass -file .\WS1Branding.ps1
- Detection method: file exists : *%ProgramData%\Airwatch\WS1Branding\WS1Branding.ps1.tag*
- Uninstall : cmd.exe /c del %ProgramData%\Airwatch\WS1Branding\WS1Branding.ps1.tag


See https://oofhours.com/2020/05/18/two-for-one-updated-autopilot-branding-and-update-os-scripts/ for more information.
