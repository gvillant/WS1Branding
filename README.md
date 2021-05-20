<p align="center">
  <a href="https://github.com/gvillant/WS1Branding/releases"><img src="https://img.shields.io/github/release/gvillant/WS1Branding?style=plastic"></a>
  <a href="https://github.com/gvillant/WS1Branding/releases"><img src="https://img.shields.io/github/release-date/gvillant/WS1Branding?style=plastic"></a>
  </p>

# 🖼️ WS1Branding
This repository contains a sample PowerShell script that can be packaged into a WS1 app to customize Windows 10 devices.

## ⚙️ Capabilities
These customizations are currently supported:

- STEP 1: Customize start menu layout. By default it will apply a simple two-icon layout (similiar to the default one on Windows 10 1903, but without the Office app).
- STEP 2: Set time zone. The time zone will be set to the specified time zone name (Pacific Standard Time by default). If time zone is not specified, then location services will be enabled to setup the timezone automatically
- STEP 3: Remove in-box provisioned apps. A list of in-box provisioned apps will be removed.
- STEP 4: Install updated OneDrive client per-machine. To support the latest OneDrive features, the client will be updated and installed per-machine (instead of the per-user default).
- STEP 5: Disable the Edge desktop icon. When using OneDrive Known Folder Move, this can cause duplicate (and unnecessary) shortcuts to be synced.
- STEP 6: Install language packs. You can embed language pack CAB files (place them into the LPs folder), and each will be automatically installed. (In a perfect world, these would be pulled from Windows Update, but there's no simple way to do that, hence the need to include these in the ZIP. You can download the language pack ISO from MSDN or VLSC.)
- STEP 7: Configure language settings. Adding a language pack isn't enough - you have to tell Windows that you want it to be configured for all users. This is done through an XML file fed to INTL.CPL; customize the file as needed. (Note this is commented out by default in the Config.xml file.)
- STEP 8: Install features on demand (FOD). Specify a list of features that you want to install, from the list at https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod. The needed components will be downloaded from Windows Update automatically and added to the running OS.
- STEP 9: Configure default apps. Import a list of file associations (as created by manually configuring the associations that you want and then using "DISM /Online /Export-DefaultAppAssociations:C:\Associations.xml" to export those settings) that should replace the default app associations. (Note that even though an example is included from a customized Windows 10 1903 image, making IE 11 the default browser, you should replace this file with your own exported version. Also, do not edit the file that you exported, e.g. to remove entries that you didn't change.)
- STEP 10: Configure the registered user and organization.
- STEP 11: Configure the "OEM" support information, you can check on settings/about.
- STEP 12: Disable network location fly-out
- STEP 13: Disable new Edge desktop icon
- STEP 14: Update OS using PSWindowsUpdate Powershell module. If enabled, the script will exit with code 3010. Today this is not supported with Dell Connected Provisioning offer. 
- WORK IN PROGRESS : Rename Computer: Only for AD On-Prem scenario, the script will rename the computer as soon as it is able to communicate with AD domain controlers. Please follow the requirements explained here : https://oofhours.com/2020/05/19/renaming-autopilot-deployed-hybrid-azure-ad-join-devices/

## 📲 Using
1. setup the config.xml file and other required files, accordingly to the customizations you decided to implement : associations.xml, Language.xml, Layout.xml, Dell.bmp, Cabs files for additional languages ... 
2. Create a file "dummyfile.exe" (the trick to be able to upload the package to ws1 as an application) 
3. Zip the folder as explain below

## 💾 Building
Zip the folder (without "extra" root folder, ie the ps1 file script should be at the higher level) then create a WS1 application with following settings:
- Install as device
- Cmdline = powershell.exe -noprofile -executionpolicy bypass -file .\WS1Branding.ps1
- Detection method: file exists : *%ProgramData%\Airwatch\WS1Branding\WS1Branding.ps1.tag*
- Uninstall : cmd.exe /c del %ProgramData%\Airwatch\WS1Branding\WS1Branding.ps1.tag

## ➕ Requirements and Dependencies
for renaming AD objects, check requirements here : https://oofhours.com/2020/05/19/renaming-autopilot-deployed-hybrid-azure-ad-join-devices/

## ✌ Others 
Forked from the script developped initially by Michael Niehaus for MS Intune https://github.com/mtniehaus/AutopilotBranding
See https://oofhours.com/2020/05/18/two-for-one-updated-autopilot-branding-and-update-os-scripts/ for more information.
