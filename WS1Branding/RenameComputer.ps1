
<#PSScriptInfo

.VERSION 1.0

.AUTHOR Gaëtan Villant

.COPYRIGHT Michael Niehaus

.LICENSEURI under MIT license

.RELEASENOTES
Version 1.0: Initial version, forked from Michael Niehaus Intune script. 
Version 1.1: 24/12/2021 : Improved Tag file detection. 

#>

<# 

.DESCRIPTION 
 This script will rename the computer in a WS1 Drop Ship provisioning environment (AD on-prem) 
 Modify the "Naming Convention" part to build your own, build the WS1 package and assign during the Drop Ship provisioning step.

#> 

Param()


# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy bypass -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

# Create a tag file just so Intune knows this was installed
if (-not (Test-Path "$($env:ProgramData)\Airwatch\WS1Branding"))
{
    Mkdir "$($env:ProgramData)\Airwatch\WS1Branding"
}
Set-Content -Path "$($env:ProgramData)\Airwatch\WS1Branding\RenameComputer.ps1.tag" -Value "Installed"

# Initialization
$dest = "$($env:ProgramData)\Airwatch\WS1Branding"
if (-not (Test-Path $dest))
{
    mkdir $dest
}
Start-Transcript "$dest\RenameComputer.log" -Append

# Make sure we are already domain-joined (Offline Domain Join has been processed)
$goodToGo = $true
$details = Get-ComputerInfo
if (-not $details.CsPartOfDomain)
{
    Write-Host "Not part of a domain."
    $goodToGo = $false
}

# Make sure we have connectivity to the Domain Controller
$dcInfo = [ADSI]"LDAP://RootDSE"
if ($dcInfo.dnsHostName -eq $null)
{
    Write-Host "No connectivity to the domain."
    $goodToGo = $false
}

if ($goodToGo)
{
    # Get the new computer name (modify the logic below to fit your own naming convention !) 
    $SerialNumber = (Get-WmiObject -Class Win32_Bios).SerialNumber
    $isLaptop = [bool](Get-WmiObject -Class Win32_SystemEnclosure | Where-Object ChassisTypes -in '{9}', '{10}', '{14}')

    $SerialNumberClean = ($SerialNumber -replace '-','')
    $SerialNumberClean = $SerialNumberClean.Substring($SerialNumberClean.Length - 7)
    $Prefix = "FR"
    
    <#  if ($isLaptop) {
            $newName = $Prefix + "L-" + $SerialNumberClean }
        else {
            $newName = $Prefix + "D-" + $SerialNumberClean }
    #>

    $newName = $Prefix + $SerialNumberClean

    # Set the computer name
    Write-Host "Renaming computer to $newName"
    Rename-Computer -NewName $newName

    # Remove the scheduled task
    Disable-ScheduledTask -TaskName "RenameComputer" -ErrorAction Ignore
    Unregister-ScheduledTask -TaskName "RenameComputer" -Confirm:$false -ErrorAction Ignore
    Write-Host "Scheduled task unregistered."
    
    # Restart the Computer renaming to take effect. 
    Write-Host "Initiating a restart in 10 minutes"
    & shutdown.exe /g /t 600 /f /c "Restarting the computer due to a computer name change.  Save your work."
    Stop-Transcript
    Exit 0
}
else
{
    # Check to see if already scheduled
    $existingTask = Get-ScheduledTask -TaskName "RenameComputer" -ErrorAction SilentlyContinue
    if ($existingTask -ne $null)
    {
        Write-Host "Scheduled task already exists."
        Stop-Transcript
        Exit 0
    }

    # Copy myself to a safe place if not already there
    if (-not (Test-Path "$dest\RenameComputer.ps1"))
    {
        Copy-Item $PSCommandPath "$dest\RenameComputer.PS1"
    }

    # Create the scheduled task action
    $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy bypass -WindowStyle Hidden -File $dest\RenameComputer.ps1"

    # Create the scheduled task trigger
    $timespan = New-Timespan -minutes 5
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -Daily -At 9am
    $triggers += New-ScheduledTaskTrigger -AtLogOn -RandomDelay $timespan
    # $triggers += New-ScheduledTaskTrigger -AtStartup -RandomDelay $timespan # Commented out because this is blocking first user login with error "cannot find object in AD" 
    
    # Register the scheduled task
    Register-ScheduledTask -User SYSTEM -Action $action -Trigger $triggers -TaskName "RenameComputer" -Description "RenameComputer" -Force
    Write-Host "Scheduled task created."
}

Stop-Transcript
