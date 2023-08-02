# This powershell script is part of WVDAdmin and Project Hydra - see https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/ for more information
# Current Version of this script: 6.6

param(
	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('Generalize','JoinDomain','DataPartition','RDAgentBootloader','RestartBootloader','StartBootloader','StartBootloaderIfNotRunning','CleanFirstStart', 'RenameComputer','RepairMonitoringAgent','RunSysprep','JoinMEMFromHybrid')]
	[string] $Mode,
	[string] $StrongGeneralize='0',
	[string] $ComputerNewname='',						#Only for SecureBoot process (workaround, normaly not used)
	[string] $LocalAdminName='localAdmin',				#Only for SecureBoot process (workaround, normaly not used)
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
	[string] $MovePagefileToC='0',
	[string] $ExpandPartition='0',
	[string] $DomainFqdn='',
	[string] $WvdRegistrationKey='',
	[string] $LogDir="$env:windir\system32\logfiles",
	[string] $HydraAgentUri='',							#Only used by Hydra
	[string] $HydraAgentSecret='',						#Only used by Hydra
	[string] $DownloadNewestAgent='0',					#Download the newes agent, event if a local agent exist
	[string] $parameters								#Additional parameters, e.g.: used to configure sysprep
)

function LogWriter($message) {
	$message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {try {write-output($message) | Out-File $LogFile -Append} catch {}}
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
function RedirectPageFileToC() {
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
function UnzipFile($zipfile, $outdir) {
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
function DownloadFile($url, $outFile) {
    $i=3
    $ok=$false;
    do {
        try {
            LogWriter("Try to download file")
			(New-Object System.Net.WebClient).DownloadFile($url,$outFile)
            $ok=$true
        } catch {
            $i--;
            if ($i -le 0) {
				LogWriter("Download failed: $_")
                throw 
            }
            LogWriter("Re-trying download after 10 seconds")
            Start-Sleep -Seconds 10
		}
    } while (!$ok)
	LogWriter("Download done")
}

function SysprepPreClean() {
	# DISM cleanup (only if forced)
	if (Test-Path "$env:windir\system32\Dism.exe") {
		LogWriter("DISM cleanup")
		Start-Process -FilePath "$env:windir\system32\Dism.exe" -Wait -ArgumentList "/online /cleanup-image /startcomponentcleanup /resetbase" -ErrorAction SilentlyContinue
	}

	# Disable reserved storage (only if forced)
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager") {
		LogWriter("Disabling reserved storage")
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "MiscPolicyInfo" -Value 2 -force  -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "PassedPolicy" -Value 0 -force  -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0 -force  -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ActiveScenario" -Value 0 -force  -ErrorAction Ignore
	}
}

function RunSysprep($parameters) {	
	# Run sysprep in another task to let the runcommand call end and monitor the sysprep log file in parallel
	Start-Process -FilePath PowerShell.exe -WorkingDirectory $LocalConfig -ArgumentList "-ExecutionPolicy Bypass -File `"$($LocalConfig)\ITPC-WVD-Image-Processing.ps1`" -Mode RunSysprep -parameters `"$($parameters)`""
}
function RunSysprepInternal($parameters) {
	LogWriter("Starting sysprep to generalize session host")
	$sysprepErrorLogFile="$env:windir\System32\Sysprep\Panther\setuperr.log"

	# Get access to the log files
	$sysPrepLogPath="$env:windir\System32\Sysprep\Panther"
	$sysPrepLogPathItem = Get-Item $sysPrepLogPath.Replace("C:\","\\localhost\\c$\") -ErrorAction Ignore
	$acl = $sysPrepLogPathItem.GetAccessControl()
	$acl.SetOwner((New-Object System.Security.Principal.NTAccount("System")))
	$sysPrepLogPathItem.SetAccessControl($acl)
	$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("System","FullControl","Allow")
	$acl.AddAccessRule($aclSystemFull)
	$sysPrepLogPathItem.SetAccessControl($acl)

	$errorReason=""
	$restrartSysprepOnce=2
	do {
		Remove-Item -Path $sysprepErrorLogFile -Force -ErrorAction Ignore
		LogWriter("Resetting sysprep state")
		Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Sysprep" -Name "SysprepCorrupt" -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "State" -Value 2 -force
		New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -force
		New-Item -Path "HKLM:\Software\Microsoft\DesiredStateConfiguration" -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DesiredStateConfiguration" -Name "AgentId" -Value "" -force  -ErrorAction Ignore

		if ($errorReason -ne "") {
			LogWriter("Patch Generalize.xml to workaround $errorReason")
			# Patch Generalize.xml
			$sysPrepActionFile="Generalize.xml"
			$sysPrepActionPath="$env:windir\System32\Sysprep\ActionFiles"
			[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
			$xml.SelectNodes("//assemblyIdentity") | ForEach-Object{
				if($_.name -match $errorReason) {$_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null}
			}
			$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
			Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old.*" -Force -ErrorAction Ignore
			Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old.$((Get-Date).ToString("yyyy-MM-dd_HH-mm-ss"))"
			Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
			LogWriter("Modifying sysprep Generalize - Done")
		}

		LogWriter("Starting sysprep executable")
		$proc=Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList $parameters -PassThru

		$restrartSysprepOnce--

		# Wait for sysprep shutdown and monitor logfile
		$again=$true
		do {
			LogWriter("Waiting for sysprep executable")
			Start-Sleep -Seconds 5
			if ((Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) -eq $null) {
				LogWriter("Sysprep executable finished")
				$again=$false
				$restrartSysprepOnce=0
			}
			$sysprepErrorLog=Get-Content -Path $sysprepErrorLogFile -ErrorAction SilentlyContinue
			if ($sysprepErrorLog) {
				$hasError=$false
				$errorReason=""
				$errorReasonFull=""
				$sysprepErrorLog | foreach {
					# check for error
					if ($_ -like "*, Error *") {
						if ($_ -like "*ExecuteInternal*") {
							$pattern = "(?<=Error in executing action for\s)(.*?)(?=;)"
							$errorReason=Select-String -InputObject $_ -Pattern $pattern -AllMatches | Foreach-Object { $_.Matches.Value }
							if ($restrartSysprepOnce -eq 0) {
								LogWriter("Sysprep failed: $_")
								throw "Sysprep failed: $_"
							}
						}
						if ($_.IndexOf(", Error      [") -gt -1) {
							$again=$false
							$hasError=$true
						}
					}
				}
				if ($hasError -and $restrartSysprepOnce -gt 0) {
					# Do one time a force clean-up for sysprep
					LogWriter("Convincing sysprep to sysprep the system")
					Start-Sleep -Seconds 5
					try {Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue} catch {}
					SysprepPreClean
				} 
				# elseif ($hasError -and $restrartSysprepOnce -le 0) {
				# 	LogWriter("Sysprep failed. Check the logfile on the temporary VM in: $sysprepErrorLogFile")
				# 	throw("Sysprep failed. Check the logfile on the temporary VM in: $sysprepErrorLogFile")
				# }
			}
		} while ($again)
	} while ($restrartSysprepOnce -gt 0)
	LogWriter("Finishing RunSysprep")
}

# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"
$unattend="PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0ndXRmLTgnPz48dW5hdHRlbmQgeG1sbnM9InVybjpzY2hlbWFzLW1pY3Jvc29mdC1jb206dW5hdHRlbmQiPjxzZXR0aW5ncyBwYXNzPSJvb2JlU3lzdGVtIj48Y29tcG9uZW50IG5hbWU9Ik1pY3Jvc29mdC1XaW5kb3dzLVNoZWxsLVNldHVwIiBwcm9jZXNzb3JBcmNoaXRlY3R1cmU9ImFtZDY0IiBwdWJsaWNLZXlUb2tlbj0iMzFiZjM4NTZhZDM2NGUzNSIgbGFuZ3VhZ2U9Im5ldXRyYWwiIHZlcnNpb25TY29wZT0ibm9uU3hTIiB4bWxuczp3Y209Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vV01JQ29uZmlnLzIwMDIvU3RhdGUiIHhtbG5zOnhzaT0iaHR0cDovL3d3dy53My5vcmcvMjAwMS9YTUxTY2hlbWEtaW5zdGFuY2UiPjxPT0JFPjxTa2lwTWFjaGluZU9PQkU+dHJ1ZTwvU2tpcE1hY2hpbmVPT0JFPjxTa2lwVXNlck9PQkU+dHJ1ZTwvU2tpcFVzZXJPT0JFPjwvT09CRT48L2NvbXBvbmVudD48L3NldHRpbmdzPjwvdW5hdHRlbmQ+"

# Define logfile
$LogFile=$LogDir+"\AVD.Customizing.log"

# Main
LogWriter("Starting ITPC-WVD-Image-Processing in mode $mode")

# Generating variables from Base64-coding
if ($LocalAdminName64) {$LocalAdminName=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminName64))}
if ($LocalAdminPassword64) {$LocalAdminPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminPassword64))}
if ($DomainJoinUserName64) {$DomainJoinUserName=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserName64))}
if ($DomainJoinUserPassword64) {$DomainJoinUserPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserPassword64))}

# Stop schedule tasks using this script
Stop-ScheduledTask  -TaskName "ITPC-AVD-CleanFirstStart-Helper" -ErrorAction SilentlyContinue
Stop-ScheduledTask  -TaskName "ITPC-AVD-Enroll-To-Intune" -ErrorAction SilentlyContinue
Stop-ScheduledTask  -TaskName "ITPC-AVD-RDAgentBootloader-Helper" -ErrorAction SilentlyContinue
Stop-ScheduledTask  -TaskName "ITPC-AVD-RDAgentBootloader-Monitor-2" -ErrorAction SilentlyContinue
Stop-ScheduledTask  -TaskName "ITPC-AVD-RDAgentBootloader-Monitor-1" -ErrorAction SilentlyContinue
Stop-ScheduledTask  -TaskName "ITPC-AVD-RDAgentMonitoring-Monitor" -ErrorAction SilentlyContinue


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
}
if ($ComputerNewname -eq "" -or $DownloadNewestAgent -eq "1") {
	if ((Test-Path ($LocalConfig+"\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
		if ((Test-Path ($ScriptRoot+"\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
			LogWriter("Downloading RDAgent")
			DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" ($LocalConfig+"\Microsoft.RDInfra.RDAgent.msi")
		} else {Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($LocalConfig+"\")}
	}
	if ((Test-Path ($LocalConfig+"\Microsoft.RDInfra.RDAgentBootLoader.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
		if ((Test-Path ($ScriptRoot+"\Microsoft.RDInfra.RDAgentBootLoader.msi ")) -eq $false -or $DownloadNewestAgent -eq "1") {
			LogWriter("Downloading RDBootloader")
			DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" ($LocalConfig+"\Microsoft.RDInfra.RDAgentBootLoader.msi")
		} else {Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($LocalConfig+"\")}
	}
}

# updating local script (from maybe an older version from the last image process)
Copy-Item "$($MyInvocation.InvocationName)" -Destination ($LocalConfig+"\ITPC-WVD-Image-Processing.ps1") -Force -ErrorAction SilentlyContinue

# check, if secure boot is enabled (used by the snapshot workaround)
$isSecureBoot=$false
try {
	$isSecureBoot=Confirm-SecureBootUEFI
}
catch {}

# try to get windows full version to do some workarounds
$is1122H2=$false
try {
    $ci=Get-ComputerInfo
    if ($ci.OsName -match "Windows 11" -and $ci.OSDisplayVersion -match "22h2") {
		$is1122H2=$true
		LogWriter("Windows 11 22H2 detected")
	}
}
catch {}

# Start script by mode
if ($mode -eq "Generalize") {
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	LogWriter("Disabling ITPC-LogAnalyticAgent and MySmartScale if exist") 
	Disable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
	Disable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore

	LogWriter("Prevent removing language packs")
	New-Item -Path "HKLM:\Software\Policies\Microsoft\Control Panel" -Name "International" -force -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -force

	
	LogWriter("Cleaning up reliability messages")
	$key="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability"
	Remove-ItemProperty -Path $key -Name "DirtyShutdown" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "DirtyShutdownTime" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "LastAliveStamp" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "TimeStampInterval" -ErrorAction Ignore

	LogWriter("Cleaning up some blocking sysprep apps")
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection" -Name "senseGuid" -ErrorAction Ignore

	# Triggering dotnet to execute queued items
	$dotnetRoot="$env:windir\Microsoft.NET\Framework"
	Get-ChildItem -Path $dotnetRoot -Directory | foreach {
		if (Test-Path "$($_.FullName)\ngen.exe") {
			LogWriter("Triggering dotnet to execute queued items in: $($_.FullName)")
			Start-Process -FilePath "$($_.FullName)\ngen.exe" -Wait -ArgumentList "ExecuteQueuedItems" -ErrorAction SilentlyContinue
		}
	}

	# Read property from registry (force imaging, like dism)
	$force=$StrongGeneralize -eq "1"
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Force") {
		$force=$true
	}

	# SysprepPreClean: DSIM and reserved storage
	if ($force) {
		SysprepPreClean	
	}
	
	# Removing the state of an olde AAD Join
	LogWriter("Cleaning up previous AADLoginExtension / AAD join")
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Azure\CurrentVersion\AADLoginForWindowsExtension"  -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin"  -Recurse -Force -ErrorAction Ignore
	$AadCert=Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -match "CN=MS-Organization-P2P-Access*"}
	if ($AadCert -ne $null) {
		$cn=$AadCert.Subject.Split(",")[0]

		LogWriter("Found probaly a AAD certificate with name: $cn")
		Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "$($cn)*"} | ForEach-Object {
			LogWriter("Deleting certificate from image with subject: $($_.Subject)")
			Remove-Item -Path $_.PSPath
		}
	}

	# Removing an old intune configuration to avoid an uninstall of installed applications
	LogWriter("Removing intune configuration")
	if ((Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue) -ne $null) {
		Stop-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue -Force
	}
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current" -Recurse -Force -ErrorAction Ignore
	Uninstall-Package -Name "Microsoft Intune Management Extension" -AllVersions -Force -ErrorAction SilentlyContinue 


	# Get access to sysprep action files
	$sysPrepActionPath="$env:windir\System32\Sysprep\ActionFiles"
	$sysPrepActionPathItem = Get-Item $sysPrepActionPath.Replace("C:\","\\localhost\\c$\") -ErrorAction Ignore
	$acl = $sysPrepActionPathItem.GetAccessControl()
	$acl.SetOwner((New-Object System.Security.Principal.NTAccount("System")))
	$sysPrepActionPathItem.SetAccessControl($acl)
	$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("System","FullControl","Allow")
	$acl.AddAccessRule($aclSystemFull)
	$sysPrepActionPathItem.SetAccessControl($acl)
	
	# Patch Generalize.xml
	$sysPrepActionFile="Generalize.xml"
	[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
	$xml.SelectNodes("//sysprepModule") | ForEach-Object{
		if($_.moduleName -match "AppxSysprep.dll") {$_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null}
	}
	$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
	Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old.*" -Force -ErrorAction Ignore
	Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old.$((Get-Date).ToString("yyyy-MM-dd_HH-mm-ss"))"
	Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
	LogWriter("Modifying sysprep Generalize - Done")
	
	# Patch Specialize.xml for Windows 11 22H2 as workaround
	if ($is1122H2) {
		LogWriter("Modifying sysprep Specialize to avoid issues with Windows 11 22H2")
		$sysPrepActionFile="Specialize.xml"
		[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
		$xml.SelectNodes("//sysprepModule") | ForEach-Object{
			if($_.methodName -eq "CryptoSysPrep_Specialize") {$_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null}
		}
		$xml.SelectNodes("//sysprepModule") | ForEach-Object{
			if($_.methodName -eq "CryptoSysPrep_Specialize") {$_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null}
		}
		$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
		Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old.*" -Force -ErrorAction Ignore
		Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old.$((Get-Date).ToString("yyyy-MM-dd_HH-mm-ss"))"
		Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
		LogWriter("Modifying sysprep Specialize - Done")
	}

	# Preparation for the snapshot workaround
	if ($isSecureBoot -and $LocalAdminName -ne "" -and $LocalAdminPassword -ne "") {
		LogWriter("Creating administrator $LocalAdminName")
		New-LocalUser "$LocalAdminName" -Password (ConvertTo-SecureString $LocalAdminPassword -AsPlainText -Force) -FullName "$LocalAdminName" -Description "Local Administrator" -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "Administrators" -Member "$LocalAdminName" -ErrorAction SilentlyContinue
	}

	LogWriter("Removing an older Sysprep state")
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Sysprep" -Name "SysprepCorrupt" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "State" -Value 2 -force
	New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -force
	New-Item -Path "HKLM:\Software\Microsoft\DesiredStateConfiguration" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DesiredStateConfiguration" -Name "AgentId" -Value "" -force  -ErrorAction Ignore

	LogWriter("Saving time zone info for re-deploy")
	$timeZone=(Get-TimeZone).Id
	LogWriter("Current time zone is: "+$timeZone)
	New-Item -Path "HKLM:\SOFTWARE" -Name "ITProCloud" -ErrorAction Ignore
	New-Item -Path "HKLM:\SOFTWARE\ITProCloud" -Name "WVD.Runtime" -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force
	
	LogWriter("Removing existing Azure Monitoring Certificates")
	Get-ChildItem "Cert:\LocalMachine\Microsoft Monitoring Agent" -ErrorAction Ignore | Remove-Item

	# Check, if the optimization script exist (Hydra: use a script inside Hydra)
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
		RedirectPageFileToC
	}

	LogWriter("Preparing sysprep to generalize session host")
	if ([System.Environment]::OSVersion.Version.Major -le 6) {
		#Windows 7
		LogWriter("Enabling RDP8 on Windows 7")
		New-Item -Path "HKLM:\SOFTWARE" -Name "Policies" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies" -Name "Microsoft" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "Windows NT" -ErrorAction Ignore
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT" -Name "Terminal Services" -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fServerEnableRDP8" -Value 1 -force
		RunSysprep "/generalize /oobe /shutdown"
		#Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown"
	} else {
		if ($isSecureBoot) {
			LogWriter("Secure boot is enabled")
			write-output([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($unattend))) | Out-File "$LocalConfig\unattend.xml" -Encoding ASCII
			write-output([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($unattend))) | Out-File "$env:windir\panther\unattend.xml" -Encoding ASCII
			RunSysprep 	"/generalize /oobe /shutdown /mode:vm /unattend:$LocalConfig\unattend.xml"
		} else {
			RunSysprep "/generalize /oobe /shutdown /mode:vm"
		}
	}

} elseif ($mode -eq "RenameComputer")
{
	# Used for the snapshot workaround
	LogWriter("Renaming computer to: "+$readComputerNewname)
	Rename-Computer -NewName $ComputerNewname -Force -ErrorAction SilentlyContinue
} elseif ($mode -eq "JoinDomain")
{	
	# Removing existing agent if exist
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	# Prevent removing language packs
	LogWriter("Prevent removing language packs")
	New-Item -Path "HKLM:\Software\Policies\Microsoft\Control Panel" -Name "International" -force -ErrorAction Ignore
	New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -force

	# Removing Intune dependency
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement" -Recurse -Force -ErrorAction Ignore

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

    # Handling workaround for Windows 11 22H2
	if ($is1122H2) {
		LogWriter("Handling workaround for Windows 11 22H2")
        # Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Ignore
		LogWriter("Running spnet.dll,Sysprep_Generalize_Net")
        Start-Process -FilePath "$($env:windir)\System32\rundll32.exe" -Wait -ArgumentList "spnet.dll,Sysprep_Generalize_Net" 
	}
	
	# AD / AAD handling
	if ($DomainJoinUserName -ne "" -and $AadOnly -ne "1") {
		LogWriter("Joining AD domain")
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
		if ($JoinMem -eq "1") {
			LogWriter("Joining Microsoft Endpoint Management is selected. Create a scheduled task to enroll in Intune after completing the hybrid join")
			$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"JoinMEMFromHybrid`""
			$trigger = @(
				$(New-ScheduledTaskTrigger -AtStartup),
				$(New-ScheduledTaskTrigger -At (Get-Date).AddMinutes(2) -Once -RepetitionInterval (New-TimeSpan -Minutes 1))
			)
			$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
			$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
			$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
			Register-ScheduledTask -TaskName "ITPC-AVD-Enroll-To-Intune" -InputObject $task -Force
		}
	} else {
		LogWriter("AAD only is selected. Skipping joining to a native AD, joining AAD")
		$aadJoinSuccessful=$false
        # check if already joined		
        $aadLoginLogfile=@(Get-ChildItem "C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\?.?.?.?\AADLoginForWindowsExtension*.*" -ErrorAction Ignore)[@(Get-ChildItem -Directory  "C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\?.?.?.?\AADLoginForWindowsExtension*.*" -ErrorAction Ignore).count-1].fullname
        if ($aadLoginLogfile -ne $null) {
            LogWriter("AAD-Logfile of aad join exist in folder: $aadLoginLogfile")
        	$aadJoinMessage=(Select-String  -Path "$aadLoginLogfile" -pattern "BadRequest")
        		if ($aadJoinMessage -ne $null) {
                    $aadJoinMessage="{"+$aadJoinMessage.ToString().split("{")[1..99]
        			# AAD join failed
        			LogWriter("AAD join failed with message: $($aadJoinMessage)")
        			throw "AAD join failed with message: `n$($aadJoinMessage)"
        		}
        	$aadJoinMessage=(Select-String  -Path "$aadLoginLogfile" -pattern "Successfully joined|Device is already secure joined")

        		if ($aadJoinMessage -ne $null) {
                    $aadJoinMessage="{"+$aadJoinMessage.ToString().split("{")[1..99]
        			# AAD join sucessful
					LogWriter("Hosts is successfully joined to AAD (reported by logfile)")
        			$aadJoinSuccessful=$true
        		}
        }
        if ($aadJoinSuccessful -eq $false) {
			LogWriter("Cleaning up previous AADLoginExtension / AAD join")
			Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Azure\CurrentVersion\AADLoginForWindowsExtension" -Force -ErrorAction Ignore
			if (Test-Path -Path "$($env:WinDir)\system32\Dsregcmd.exe") {
				LogWriter("Leaving old AAD")
				Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/leave" -ErrorAction SilentlyContinue
			}
    		LogWriter("Running AADLoginForWindows")
    		$aadPath=@(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows")[@(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows").count-1].fullname
    		Start-Process -wait -LoadUserProfile -FilePath "$aadPath\AADLoginForWindowsHandler.exe" -WorkingDirectory "$aadPath" -ArgumentList 'enable' -RedirectStandardOutput "$($LogDir)\Avd.AadJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.AadJoin.Warning.txt"
        }
		if ($JoinMem -eq "1") {
			LogWriter("Joining Microsoft Endpoint Management is selected. Try to register to MEM")
			Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/AzureSecureVMJoin /debug /MdmId 0000000a-0000-0000-c000-000000000000" -RedirectStandardOutput "$($LogDir)\Avd.MemJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.MemJoin.Warning.txt"
		}
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
			} else {$modifyDrives=$false}
		}
	}
	
	# resize C: partition to fill up the disk if ExpandPartition!="0""
	if ($ExpandPartition -ne "0" -and $modifyDrives -eq $false)
	{
		LogWriter("Check C: partition for resizing")
		try {
			$defragSvc=Get-Service -Name defragsvc -ErrorAction SilentlyContinue
			Set-Service -Name defragsvc -StartupType Manual -ErrorAction SilentlyContinue
			$supportedSize = (Get-PartitionSupportedSize -DriveLetter "c" -ErrorAction Stop)
			if ((Get-Partition -DriveLetter "c").Size -lt $supportedSize.SizeMax) {
				LogWriter("Resize C: partition to fill up the disk")
				Resize-Partition -DriveLetter "c" -Size $supportedSize.SizeMax
			}
			Set-Service -Name defragsvc -StartupType $defragSvc.StartType -ErrorAction SilentlyContinue
		} catch {
			LogWriter("Resize C: partition failed: $_")
		}
	}

	# check to move pagefile finally to C
	if ($MovePagefileToC -eq "1") {
		RedirectPageFileToC

	}
	# install Hydra Agent (Hydra only)
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
			DownloadFile $DownloadAdress "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.zip"

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
			LogWriter("An error occurred while installing Hydra Agent: $_")
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

				$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"StartBootloaderIfNotRunning`""
				$task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settingsSet 
				Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-2' -InputObject $task -ErrorAction Ignore
				Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-2'
				LogWriter("Added new startup task to monitor the RDAgentBootloader")

					
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
				DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3JZCm" "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi"
			}
			if ((Test-Path "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi") -eq $false) {
				LogWriter("Downloading Microsoft.RDInfra.WVDAgentManager.msi")
				DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3K2e3" "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi"
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
} elseif ($Mode -eq "RunSysprep") {
	RunSysprepInternal $parameters
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
	Start-Sleep -Seconds 60
    LogWriter "Creating task to monitor the AVDAgent Monitoring"
    $principal = New-ScheduledTaskPrincipal 'NT Authority\SYSTEM' -RunLevel Highest
    $class = cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
    $triggerM = $class | New-CimInstance -ClientOnly
    $triggerM.Enabled = $true
    $triggerM.Subscription='<QueryList><Query Id="0" Path="RemoteDesktopServices"><Select Path="RemoteDesktopServices">*[System[Provider[@Name=''Microsoft.RDInfra.RDAgent.Service.MonitoringAgentCheck'']] and System[(Level=3) and (Task=0) and (EventID=0)]]</Select></Query></QueryList>'
    $actionM = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"RepairMonitoringAgent`""
    $settingsM = New-ScheduledTaskSettingsSet
    $taskM = New-ScheduledTask -Action $actionM -Principal $principal -Trigger $triggerM -Settings $settingsM -Description "Repairs the Azure Monitoring Agent in case of an issue"
    Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentMonitoring-Monitor' -InputObject $taskM #-ErrorAction Ignore
    Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentMonitoring-Monitor' -ErrorAction Ignore
	LogWriter "Monitoring the agent state on the first start to handle the SXS-Stack issue"
	$run=$true
	$counter=0
	do {
		$avdAgentStateJson=(Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\HealthCheckReport" -ErrorAction Ignore)."AgentHealthCheckReport"
		if ($avdAgentStateJson -ne $null) {
			LogWriter "Got an AVD agent state"
			if ($avdAgentStateJson -like "*SxsStack listener is not ready*") {
				LogWriter "SxsStack listener is not ready / restarting bootloader" 
				Stop-Service -Name "RDAgentBootLoader"
				Start-Service -Name "RDAgentBootLoader"
				Start-Sleep -Seconds 60
				$counter=$counter+10
			}
		}
		$counter++
		if ($counter -gt 60) {$run=$false}
		Start-Sleep -Seconds 10
	} while ($run)
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
}  elseif ($mode -eq "RepairMonitoringAgent") {
	$LogFile=$LogDir+"\AVD.MonitorReinstall.log"
    $files=@(Get-ChildItem -Path "$($env:ProgramFiles)\Microsoft RDInfra\Microsoft.RDInfra.Geneva.Installer*.msi")
    if ($files.Length -eq 0) {
        LogWriter "Couldn't find binaries"
    } else {
        $file=$files[$files.Length-1]
        LogWriter "Installing Monitoring Agent $file"
        Start-Process -wait -FilePath "$file" -ArgumentList "/quiet /qn /norestart /passive /l*v `"$($env:windir)\system32\logfiles\AVD-MonitoringAgentMsi.log`""
    }
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
}  elseif ($mode -eq "StartBootloaderIfNotRunning") {
	$interval=30
	$run=$true
	$counter=0
	$serviceName="RDAgentBootLoader"
	do {
		Start-Sleep -Seconds $interval
		$service=Get-Service -Name $serviceName -ErrorAction SilentlyContinue
		if ($service -ne $null -and $service.Status -ne [System.ServiceProcess.ServiceControllerStatus](4)) {
			LogWriter "Starting service: $serviceName"
			Start-Service -Name $serviceName -ErrorAction SilentlyContinue
		}
		$counter++
		if ($counter -gt 10) {$interval=90}
		if ($counter -gt 20) {$run=$false}
	} while ($run)
}  elseif ($mode -eq "JoinMEMFromHybrid") {
    # Check, if registry key exist
    if ($null -ne (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*" -ErrorAction SilentlyContinue)) {
        LogWriter("Device is AAD joined")
        if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement") {
            LogWriter("Device is Intune managed")
            LogWriter("Removing schedule task")
            Unregister-ScheduledTask -TaskName "ITPC-AVD-Enroll-To-Intune" -Confirm:$false
        } else {
            LogWriter("Device is not Intune managed - starting registration")
            Start-Process -FilePath "$($env:windir)\System32\deviceenroller.exe" -ArgumentList "/c /AutoEnrollMDMUsingAADDeviceCredential" -Wait -NoNewWindow
        }
    } else {
        LogWriter("Device is not AAD joined")
		if (Test-Path -Path "$($env:WinDir)\system32\Dsregcmd.exe") {
				LogWriter("Triggering AAD join")
				Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/join" -ErrorAction SilentlyContinue
		}
	}
}