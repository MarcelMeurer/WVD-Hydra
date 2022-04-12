# This powershell script is part of WVDAdmin and Project Hydra - see https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/ for more information
# Current Version of this script: 4.2

param(

	[string] $Secret='',

	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('Generalize','JoinDomain','DataPartition','RDAgentBootloader','RestartBootloader','StartBootloader','CleanFirstStart')]
	[string] $Mode,
	[string] $LocalAdminName='localAdmin',				#Currently not used in this script
	[string] $LocalAdminPassword='',
	[string] $DomainJoinUserName='',
	[string] $DomainJoinUserPassword='',
	[string] $LocalAdminName64='bG9jYWxBZG1pbg==',		#Base64-coding is used if not empty - providing the older parameters to be compatible
	[string] $LocalAdminPassword64='',
	[string] $DomainJoinUserName64='',
	[string] $DomainJoinUserPassword64='',
	[string] $DomainJoinOU='',
	[string] $AadOnly='0',
	[string] $JoinMem='0',
	[string] $DomainFqdn='',
	[string] $WvdRegistrationKey='',
	[string] $LogDir="$env:windir\system32\logfiles",
    [string] $HydraAgentUri='',
    [string] $HydraAgentSecret=''
)

function LogWriter($message) {
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}
function ShowDrives() {
	$drives = Get-WmiObject -Class win32_volume -Filter "DriveType = 3"	

	LogWriter("Drives:")
	foreach ($drive in $drives) {
		LogWriter("Name: '$($drive.Name)', Letter: '$($drive.DriveLetter)', Label: '$($drive.Label)'")
	}
}
function ShowPageFiles() {
	$pageFiles = Get-WmiObject -Class Win32_PageFileSetting	

	LogWriter("Pagefiles:")
	foreach ($pageFile in $pageFiles) {
		LogWriter("Name: '$($pageFile.Name)', Maximum size: '$($pageFile.MaximumSize)'")
	}
}

function UnzipFile ($zipfile, $outdir)
{
    # Based on https://gist.github.com/nachivpn/3e53dd36120877d70aee
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $files = [System.IO.Compression.ZipFile]::OpenRead($zipfile)
    foreach ($entry in $files.Entries)
    {
        $targetPath = [System.IO.Path]::Combine($outdir, $entry.FullName)
        $directory = [System.IO.Path]::GetDirectoryName($targetPath)
       
        if(!(Test-Path $directory )){
            New-Item -ItemType Directory -Path $directory | Out-Null 
        }
        if(!$targetPath.EndsWith("/")){
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true);
        }
    }
}
                                                        
# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"

# Define logfile
$LogFile=$LogDir+"\AVD.Customizing.log"

# Main
LogWriter("Starting ITPC-WVD-Image-Processing in mode ${Mode}")

# Generating variables from Base64-coding
if ($LocalAdminName64) {$LocalAdminName=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminName64))}
if ($LocalAdminPassword64) {$LocalAdminPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminPassword64))}
if ($DomainJoinUserName64) {$DomainJoinUserName=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserName64))}
if ($DomainJoinUserPassword64) {$DomainJoinUserPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserPassword64))}

# check for the existend of the helper scripts
if ((Test-Path ($LocalConfig+"\ITPC-WVD-Image-Processing.ps1")) -eq $false) {
	# Create local directory for script(s) and copy files (including the RD agent and boot loader - rename it to the specified name)
	LogWriter("Copy files to local session host or downloading files from Microsoft")
	new-item $LocalConfig -ItemType Directory -ErrorAction Ignore
	try {(Get-Item $LocalConfig -ErrorAction Ignore).attributes="Hidden"} catch {}

	if ((Test-Path ("${PSScriptRoot}\ITPC-WVD-Image-Processing.ps1")) -eq $false) {
		LogWriter("Creating ITPC-WVD-Image-Processing.ps1")
		Copy-Item "$($MyInvocation.InvocationName)" -Destination ($LocalConfig+"\ITPC-WVD-Image-Processing.ps1")
	} else {Copy-Item "${PSScriptRoot}\ITPC-WVD-Image-Processing.ps1" -Destination ($LocalConfig+"\")}


	if ((Test-Path ($ScriptRoot+"\Microsoft.RDInfra.RDAgent.msi")) -eq $false) {
		LogWriter("Downloading RDAgent")
		Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" -OutFile ($LocalConfig+"\Microsoft.RDInfra.RDAgent.msi")
	} else {Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($LocalConfig+"\")}
	if ((Test-Path ($ScriptRoot+"\Microsoft.RDInfra.RDAgentBootLoader.msi ")) -eq $false) {
		LogWriter("Downloading RDBootloader")
		Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" -OutFile ($LocalConfig+"\Microsoft.RDInfra.RDAgentBootLoader.msi")
	} else {Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($LocalConfig+"\")}
}

# updating local script (from maybe an older version from the last image process)
Copy-Item "$($MyInvocation.InvocationName)" -Destination ($LocalConfig+"\ITPC-WVD-Image-Processing.ps1") -Force -ErrorAction SilentlyContinue


if ($mode -eq "Generalize") {
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	LogWriter("Disabling ITPC-LogAnalyticAgent and MySmartScale if exist") 
	Disable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
	Disable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore
	
	LogWriter("Cleaning up reliability messages")
	$key="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability"
	Remove-ItemProperty -Path $key -Name "DirtyShutdown" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "DirtyShutdownTime" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "LastAliveStamp" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "TimeStampInterval" -ErrorAction Ignore
	
	LogWriter("Modifying sysprep to avoid issues with AppXPackages - Start")
	$sysPrepActionPath="$env:windir\System32\Sysprep\ActionFiles"
	$sysPrepActionFile="Generalize.xml"
	$sysPrepActionPathItem = Get-Item $sysPrepActionPath.Replace("C:\","\\localhost\\c$\") -ErrorAction Ignore
	$acl = $sysPrepActionPathItem.GetAccessControl()
	$acl.SetOwner((New-Object System.Security.Principal.NTAccount("SYSTEM")))
	$sysPrepActionPathItem.SetAccessControl($acl)
	$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")
	$acl.AddAccessRule($aclSystemFull)
	$sysPrepActionPathItem.SetAccessControl($acl)
	[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
	$xmlNode=$xml.sysprepInformation.imaging | where {$_.sysprepModule.moduleName -match "AppxSysprep.dll"}
	if ($xmlNode -ne $null) {
		$xmlNode.ParentNode.RemoveChild($xmlNode)
		$xml.sysprepInformation.imaging.Count
		$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
		Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old" -Force -ErrorAction Ignore
		Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old"
		Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
		LogWriter("Modifying sysprep to avoid issues with AppXPackages - Done")
	}

	
	LogWriter("Removing an older Sysprep state")
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Sysprep" -Name "SysprepCorrupt" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "State" -Value 2 -force
	New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -force

	LogWriter("Saving time zone info for re-deploy")
	$timeZone=(Get-TimeZone).Id
	LogWriter("Current time zone is: "+$timeZone)
	New-Item -Path "HKLM:\SOFTWARE" -Name "ITProCloud" -ErrorAction Ignore
	New-Item -Path "HKLM:\SOFTWARE\ITProCloud" -Name "WVD.Runtime" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force
	
	LogWriter("Removing existing Azure Monitoring Certificates")
	Get-ChildItem "Cert:\LocalMachine\Microsoft Monitoring Agent" -ErrorAction Ignore | Remove-Item

	if ([System.IO.File]::Exists("C:\ProgramData\Optimize\Win10_VirtualDesktop_Optimize.ps1")) {
		LogWriter("Running VDI Optimization script")
		Start-Process -wait -FilePath PowerShell.exe -WorkingDirectory "C:\ProgramData\Optimize" -ArgumentList '-ExecutionPolicy Bypass -File "C:\ProgramData\Optimize\Win10_VirtualDesktop_Optimize.ps1 -AcceptEULA -Optimizations WindowsMediaPlayer,AppxPackages,ScheduledTasks,DefaultUserSettings,Autologgers,Services,NetworkOptimizations"' -RedirectStandardOutput "$($LogDir)\VirtualDesktop_Optimize.Stage1.Out.txt" -RedirectStandardError "$($LogDir)\VirtualDesktop_Optimize.Stage1.Warning.txt"
	}

	# prepare cleanup task for new deployed VMs - solve an issue with the runcommand api giving older log data
	LogWriter("Preparing CleanFirstStart task")
	$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"CleanFirstStart`""
	$trigger = New-ScheduledTaskTrigger	-AtStartup
	$principal = New-ScheduledTaskPrincipal 'NT Authority\SYSTEM' -RunLevel Highest
	$settingsSet = New-ScheduledTaskSettingsSet
	$task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settingsSet 
	Register-ScheduledTask -TaskName 'ITPC-AVD-CleanFirstStart-Helper' -InputObject $task -ErrorAction Ignore
	Enable-ScheduledTask -TaskName 'ITPC-AVD-CleanFirstStart-Helper'
	LogWriter("Added new startup task to run the CleanFirstStart")

	# check if D:-drive not the temporary storage and having three drives 
	$modifyDrives=$false
	$disks=Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }
	foreach ($disk in $disks) {if ($disk.Name -ne 'D:\' -and $disk.Label -eq 'Temporary Storage') {$modifyDrives=$true}}
	if ($disks.Count -eq 3 -and $modifyDrives) {
		LogWriter("VM with 3 drives so prepare change of drive letters of temp and data after deployment")
		New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "ChangeDrives" -Value 1 -force

		# check if default value 'automatic manage pagefile size for all devices' is activated 
		if ($null -eq (Get-WmiObject Win32_Pagefile) ) {
			# disable 'automatic manage pagefile size for all devices'
			$sys = Get-WmiObject Win32_Computersystem -EnableAllPrivileges
			$sys.AutomaticManagedPagefile = $false
			$sys.put()
			LogWriter("Automatic manage pagefile size for all devices deactivated")
		}
		else {
			LogWriter("Automatic manage pagefile size for all devices not activated")
		}

		# redirect pagefile to C: to rename data partition after deployment
		$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
		LogWriter("Pagefile name: '$($CurrentPageFile.Name)', max size: $($CurrentPageFile.MaximumSize)")
		$CurrentPageFile.delete()
		LogWriter("Pagefile deleted")
		$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
		if ($null -eq $CurrentPageFile) {
			LogWriter("Pagefile deletion successful")
		}
		else {
			LogWriter("Pagefile deletion failed")
		}
		Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name='c:\pagefile.sys';InitialSize = 0; MaximumSize = 0}
		$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
		if ($null -eq $CurrentPageFile) {
			LogWriter("Pagefile not found")
		}
		else {
			LogWriter("New pagefile name: '$($CurrentPageFile.Name)', max size: $($CurrentPageFile.MaximumSize)")
		}
	}
	
	LogWriter("Starting sysprep to generalize session host")

	if ([System.Environment]::OSVersion.Version.Major -le 6) {
		#Windows 7
		LogWriter("Enabling RDP8 on Windows 7")
		New-Item -Path "HKLM:\SOFTWARE" -Name "Policies" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies" -Name "Microsoft" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "Windows NT" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT" -Name "Terminal Services" -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fServerEnableRDP8" -Value 1 -force
		Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown"
	} else {
		Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown /mode:vm"
	}

} elseif ($mode -eq "JoinDomain")
{	
	# Removing existing agent if exist
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	# Storing AadOnly to registry
	LogWriter("Storing AadOnly to registry: "+$AadOnly)
	New-Item -Path "HKLM:\SOFTWARE" -Name "ITProCloud" -ErrorAction Ignore
	New-Item -Path "HKLM:\SOFTWARE\ITProCloud" -Name "WVD.Runtime" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "AadOnly" -Value $AadOnly -force

	# Checking for a saved time zone information
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime") {
		$timeZone=(Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -ErrorAction Ignore)."TimeZone.Origin"
		if ($timeZone -ne "" -and $timeZone -ne $null) {
			LogWriter("Setting time zone to: "+$timeZone)
			Set-TimeZone -Id $timeZone
		}
	}
	if ($DomainJoinUserName -ne "" -and $AadOnly -ne "1") {
		LogWriter("Joining domain")
		$psc = New-Object System.Management.Automation.PSCredential($DomainJoinUserName, (ConvertTo-SecureString $DomainJoinUserPassword -AsPlainText -Force))

		$retry=3
		$ok=$false
		do{
			try {
				if ($DomainJoinOU -eq "")
				{
					Add-Computer -DomainName $DomainFqdn -Credential $psc -Force -ErrorAction Stop
					$ok=$true
					LogWriter("Domain joined successfully")
				} 
				else
				{
					Add-Computer -DomainName $DomainFqdn -OUPath $DomainJoinOU -Credential $psc -Force -ErrorAction Stop
					$ok=$true
					LogWriter("Domain joined successfully")
				}
			} catch {
				if ($retry -eq 0) {throw $_}
				$retry--
				LogWriter("Retry domain join because of an error: $_")
				Start-Sleep -Seconds 10
			}
		} while($ok -ne $true)
	} else {
		LogWriter("AAD only is selected. Skipping joining to a native AD, joining AAD")
		$aadPath=@(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows")[@(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows").count-1].fullname
		Start-Process -wait -FilePath "$aadPath\AADLoginForWindowsHandler.exe" -WorkingDirectory $aadPath -ArgumentList 'enable' -RedirectStandardOutput "$($LogDir)\Avd.AadJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.AadJoin.Warning.txt"
		if ($JoinMem -eq "1") {
			LogWriter("Joining Microsoft Endpoint Manamgement is selected. Try to register to MEM")
			Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/AzureSecureVMJoin /debug /MdmId 0000000a-0000-0000-c000-000000000000" -RedirectStandardOutput "$($LogDir)\Avd.MemJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.MemJoin.Warning.txt"
		}
		try {
			if ($AadOnly) {
				$timeOut=(Get-Date).AddSeconds(5*60)
				do 
				{
					LogWriter("Waiting for the domain join")
					Start-Sleep -Seconds 3#AzureAdJoined : YES
				} while ((Get-Date) -le $timeOut -and (Select-String  -InputObject (&dsregcmd /status) -pattern "AzureAdJoined : YES").length -eq 0) 
			}
		} catch {}
	}
	# check for disk handling
	$modifyDrives=$false
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime") {
		if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime").ChangeDrives -eq 1) {
			$disks=Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }
			foreach ($disk in $disks) {if ($disk.Name -eq 'D:\' -and $disk.Label -eq 'Temporary Storage') {$modifyDrives=$true}}
				if ($modifyDrives -and $disks.Count -eq 3) {
				# change drive letters of temp and data drive for VMs with 3 drives
				LogWriter("VM with 3 drives so delete old pagefile and install runonce key")

				# create scheduled task executed at startup for next phase
				$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"DataPartition`""
				$trigger = New-ScheduledTaskTrigger	-AtStartup
				$principal = New-ScheduledTaskPrincipal 'NT Authority\SYSTEM' -RunLevel Highest
				$settingsSet = New-ScheduledTaskSettingsSet
				$task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settingsSet
				Register-ScheduledTask -TaskName 'ITPC-AVD-Disk-Mover-Helper' -InputObject $task -ErrorAction Ignore
				Enable-ScheduledTask -TaskName 'ITPC-AVD-Disk-Mover-Helper'
				LogWriter("Added new startup task for the disk handling")

				# change c:\pagefile.sys to e:\pagefile.sys
				ShowPageFiles
				$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
				if ($null -eq $CurrentPageFile) {
					LogWriter("No pagefile found")
				}
				else {
					if ($CurrentPageFile.Name.tolower().contains('d:')) {
						$CurrentPageFile.delete()
						LogWriter("Old pagefile deleted")	

						Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name='c:\pagefile.sys';InitialSize = 0; MaximumSize = 0}
						LogWriter("Set pagefile to c:\pagefile.sys")
						ShowPageFiles
					}
				}
				ShowPageFiles
			}
		}
	}

	# install Hydra Agent
	if ($HydraAgentUri -ne "") {
		$uri=$HydraAgentUri
		$secret=$HydraAgentSecret
		$DownloadAdress="https://$($uri)/Download/HydraAgent"
		try {
			if ((Test-Path ("$env:ProgramFiles\ITProCloud.de")) -eq $false) {
				new-item "$env:ProgramFiles\ITProCloud.de" -ItemType Directory -ErrorAction Ignore
			}
			if ((Test-Path ("$env:ProgramFiles\ITProCloud.de\HydraAgent")) -eq $false) {
				new-item "$env:ProgramFiles\ITProCloud.de\HydraAgent" -ItemType Directory -ErrorAction Ignore
			}
			Remove-Item -Path "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.zip" -Force -ErrorAction Ignore


			LogWriter("Downloading HydraAgent.zip from $DownloadAdress")
			Invoke-WebRequest -Uri $DownloadAdress -OutFile "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.zip"

			# Stop a running instance
			LogWriter("Stop a running instance")
			Stop-ScheduledTask -TaskName 'ITPC-AVD-Hydra-Helper' -ErrorAction Ignore
			Stop-Process -Name HydraAgent -Force -ErrorAction Ignore
			Start-Sleep -Seconds 6
			UnzipFile "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.zip" "$env:ProgramFiles\ITProCloud.de\HydraAgent"

			# Configuring the agent
			LogWriter("Configuring the agent")
			cd "$env:ProgramFiles\ITProCloud.de\HydraAgent"
			. "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.exe" -i -u "wss://$($uri)/wsx" -s $secret
		}
		catch {
			LogWriter="An error occurred while installing Hydra Agent: $_"
		}
	}

	# install AVD Agent if a registration key given
	if ($WvdRegistrationKey -ne "") {
		if ([System.Environment]::OSVersion.Version.Major -gt 6) {
			LogWriter("Installing AVD agent")
			Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgent.msi" -ArgumentList "/quiet /qn /norestart /passive RegistrationToken=${WvdRegistrationKey}"

			if ($false) {
				LogWriter("Installing AVD boot loader - current path is ${LocalConfig}")
				Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgentBootLoader.msi" -ArgumentList "/quiet /qn /norestart /passive"
				LogWriter("Waiting for the service RDAgentBootLoader")
				$bootloaderServiceName = "RDAgentBootLoader"
				$retryCount = 0
				while ( -not (Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue)) {
					$retry = ($retryCount -lt 6)
					LogWriter("Service RDAgentBootLoader was not found")
					if ($retry) { 
						LogWriter("Retrying again in 30 seconds, this will be retry $retryCount")
					} 
					else {
						LogWriter("Retry limit exceeded" )
						throw "RDAgentBootLoader didn't become available after 6 retries"
					}            
					$retryCount++
					Start-Sleep -Seconds 30
				}
			} else {
				LogWriter("Preparing AVD boot loader task")
				$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"RDAgentBootloader`""
				$trigger = New-ScheduledTaskTrigger	-AtStartup
				$principal = New-ScheduledTaskPrincipal 'NT Authority\SYSTEM' -RunLevel Highest
				$settingsSet = New-ScheduledTaskSettingsSet
				$task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settingsSet 
				Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Helper' -InputObject $task -ErrorAction Ignore
				Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Helper'
				LogWriter("Added new startup task to run the RDAgentBootloader")
					
				$class = cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
				$triggerM = $class | New-CimInstance -ClientOnly
				$triggerM.Enabled = $true
				$triggerM.Subscription='<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name=''WVD-Agent'']] and System[(Level=2) and (EventID=3277)]]</Select></Query></QueryList>'
				$actionM = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"RestartBootloader`""
				$settingsM = New-ScheduledTaskSettingsSet
				$taskM = New-ScheduledTask -Action $actionM -Principal $principal -Trigger $triggerM -Settings $settingsM -Description "Restarts the bootloader in case of an known issue (timeout, download error) while installing the RDagent"
				Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-1' -InputObject $taskM -ErrorAction Ignore
				Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-1' -ErrorAction Ignore
				LogWriter("Added new task to monitor the RDAgentBootloader")
			}
		} else {
			if ((Test-Path "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi") -eq $false) {
				LogWriter("Downloading Microsoft.RDInfra.WVDAgent.msi")
				Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3JZCm' -OutFile "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi"
			}
			if ((Test-Path "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi") -eq $false) {
				LogWriter("Downloading Microsoft.RDInfra.WVDAgentManager.msi")
				Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3K2e3' -OutFile "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi"
			}
			LogWriter("Installing AVDAgent")
			Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi" -ArgumentList "/q RegistrationToken=${WvdRegistrationKey}"
			LogWriter("Installing AVDAgentManager")
			Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi" -ArgumentList '/q'
		}
	}
	LogWriter("Enabling ITPC-LogAnalyticAgent and MySmartScale if exist") 
	Enable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
	Enable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore

	if ([System.IO.File]::Exists("C:\ProgramData\Optimize\Win10_VirtualDesktop_Optimize.ps1")) {
		LogWriter("Running VDI Optimization script")
		Start-Process -wait -FilePath PowerShell.exe -WorkingDirectory "C:\ProgramData\Optimize" -ArgumentList '-ExecutionPolicy Bypass -File "C:\ProgramData\Optimize\Win10_VirtualDesktop_Optimize.ps1 -AcceptEULA -Optimizations WindowsMediaPlayer,AppxPackages,ScheduledTasks,DefaultUserSettings,Autologgers,Services,NetworkOptimizations"' -RedirectStandardOutput "$($LogDir)\VirtualDesktop_Optimize.Stage2.Out.txt" -RedirectStandardError "$($LogDir)\VirtualDesktop_Optimize.Stage2.Warning.txt"
	}

	# Final reboot
	LogWriter("Finally restarting session host")
	Restart-Computer -Force -ErrorAction SilentlyContinue
} elseif ($Mode -eq "DataPartition") {

	if ((Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }).Count -eq 3) {
		# change drive letters of temp and data drive for VMs with 3 drives
		LogWriter("VM with 3 drives so change drive letters of temp and data")

		ShowDrives

		# change c:\pagefile.sys to e:\pagefile.sys
		ShowPageFiles
		$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
		if ($null -eq $CurrentPageFile) {
			LogWriter("No pagefile found")
		}
		else {
			if ($CurrentPageFile.Name.tolower().contains('c:')) {

				ShowDrives

				# change temp drive to Z:
				$drive = Get-WmiObject -Class win32_volume -Filter "DriveLetter = 'd:'"
				if ($null -ne $drive) {
					LogWriter("d: drive: $($drive.Label)")
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter='z:' }
					LogWriter("changed drive letter to z:")
					ShowDrives
				}
				else {
					LogWriter("Drive D: not found")
				}
		
				# change data drive to D: 
				$drive = Get-WmiObject -Class win32_volume -Filter "DriveLetter = 'e:'"
				if ($null -ne $drive) {
					LogWriter("e: drive: $($drive.Label)")
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter='D:' }
					LogWriter("changed drive letter to D:")
					ShowDrives
				}
				else {
					LogWriter("Drive E: not found")
				}
		
				# change temp drive back to E: 
				$drive = Get-WmiObject -Class win32_volume -Filter "DriveLetter = 'z:'"
				if ($null -ne $drive) {
					LogWriter("z: drive: $($drive.Label)")
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter='E:' }
					LogWriter("changed drive letter to E:")
					ShowDrives
				}
				else {
					LogWriter("Drive Z: not found")
				}
		
				# change c:\pagefile.sys to e:\pagefile.sys
				ShowPageFiles
				$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
				if ($null -eq $CurrentPageFile) {
					LogWriter("No pagefile found")
				}
				else {
					$CurrentPageFile.delete()
					LogWriter("Old pagefile deleted")	
				}
				ShowPageFiles
		
		
				Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name='e:\pagefile.sys';InitialSize = 0; MaximumSize = 0}
				LogWriter("set pagefile to e:\pagefile.sys")
				ShowPageFiles

				# reboot to activate pagefile
				LogWriter("Finally restarting session host")
				Restart-Computer -Force
				LogWriter("After Finally restarting session host")
			}
		}
	}
	LogWriter("Disable scheduled task")
	try {
		# disable startup scheduled task
		Disable-ScheduledTask -TaskName 'ITPC-AVD-Disk-Mover-Helper'
	}
	catch {
		LogWriter("Disabling scheduled task failed: " + $_.Exception.Message)
	}
} elseif ($Mode -eq "RDAgentBootloader") {
	LogWriter("Installing AVD boot loader - current path is ${LocalConfig}")
	Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgentBootLoader.msi" -ArgumentList "/quiet /qn /norestart /passive"
	LogWriter("Waiting for the service RDAgentBootLoader")
	$bootloaderServiceName = "RDAgentBootLoader"
	$retryCount = 0
	while ( -not (Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue)) {
		$retry = ($retryCount -lt 6)
		LogWriter("Service RDAgentBootLoader was not found")
		if ($retry) { 
			LogWriter("Retrying again in 30 seconds, this will be retry $retryCount")
		} 
		else {
			LogWriter("Retry limit exceeded" )
			throw "RDAgentBootLoader didn't become available after 6 retries"
		}            
		$retryCount++
		Start-Sleep -Seconds 30
	}
	LogWriter("Disable scheduled task")
	try {
		# disable startup scheduled task
		Disable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Helper'
	}
	catch {
		LogWriter("Disabling scheduled task failed: " + $_.Exception.Message)
	}
} elseif ($Mode -eq "CleanFirstStart") {
	LogWriter("Cleaning up Azure Agent logs - current path is ${LocalConfig}")
	Remove-Item -Path "C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\*" -Include *.status  -Recurse -Force -ErrorAction SilentlyContinue
	LogWriter("Disable scheduled task")
	try {
		# disable startup scheduled task
		Disable-ScheduledTask -TaskName 'ITPC-AVD-CleanFirstStart-Helper'
	}
	catch {
		LogWriter("Disabling scheduled task failed: " + $_.Exception.Message)
	}
}  elseif ($mode -eq "RestartBootloader") {
    $LogFile=$LogDir+"\AVD.AgentBootloaderErrorHandling.log"
    LogWriter "Stopping service"
    Stop-Service -Name "RDAgentBootLoader"
    LogWriter "Starting service"
    Start-Service -Name "RDAgentBootLoader"
}  elseif ($mode -eq "StartBootloader") {
    $LogFile=$LogDir+"\AVD.AgentBootloaderErrorHandling.log"
    LogWriter "Start service was triggered by an event"
    LogWriter "Waiting for 5 seconds"
    Start-Sleep -Seconds 5
    LogWriter "Starting service"
    Start-Service -Name "RDAgentBootLoader"
    LogWriter "Waiting for 60 seconds"
    Start-Sleep -Seconds 60
    LogWriter "Starting service (if not running)"
    Start-Service -Name "RDAgentBootLoader"
    LogWriter "Waiting for 60 seconds"
    Start-Sleep -Seconds 60
    LogWriter "Starting service (if not running)"
    Start-Service -Name "RDAgentBootLoader"
} 