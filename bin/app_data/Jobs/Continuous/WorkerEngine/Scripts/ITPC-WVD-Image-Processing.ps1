# This powershell script is part of WVDAdmin and Project Hydra - see https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/ for more information
# Current Version of this script: 10.5
param(
	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('Generalize', 'JoinDomain', 'DataPartition', 'RDAgentBootloader', 'RestartBootloader', 'StartBootloader', 'StartBootloaderIfNotRunning', 'ApplyOsSettings', 'CleanFirstStart', 'RenameComputer', 'RepairMonitoringAgent', 'RunSysprep', 'JoinMEMFromHybrid')]
	[string] $Mode,
	[string] $StrongGeneralize = '0',
	[string] $ComputerNewname = '', 					#Only for SecureBoot process (workaround, normaly not used)
	[string] $LocalAdminName = 'localAdmin', 			#Only for SecureBoot process (workaround, normaly not used)
	[string] $LocalAdminPassword = '',
	[string] $DomainJoinUserName = '',
	[string] $DomainJoinUserPassword = '',
	[string] $LocalAdminName64 = 'bG9jYWxBZG1pbg==', 	#Base64-coding is used if not empty - providing the older parameters to be compatible
	[string] $LocalAdminPassword64 = '',
	[string] $DomainJoinUserName64 = '',
	[string] $DomainJoinUserPassword64 = '',
	[string] $AltAvdAgentDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcm1Ydg==',
	[string] $AltAvdBootloaderDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcnhySA==',
	[string] $DomainJoinOU = '',
	[string] $AadOnly = '0',
	[string] $JoinMem = '0',
	[string] $MovePagefileToC = '0',
	[string] $ExpandPartition = '0',
	[string] $DomainFqdn = '',
	[string] $WvdRegistrationKey = '',
	[string] $LogDir = "$env:windir\system32\logfiles",
	[string] $HydraAgentUri = '', 						#Only used by Hydra
	[string] $HydraAgentSecret = '', 					#Only used by Hydra
	[string] $DownloadNewestAgent = '0', 				#Download the newes agent, event if a local agent exist
	[string] $WaitForHybridJoin = '0',					#Awaits the completion of a hybrid join before joining the host pool
	[string] $parameters								#Additional parameters, e.g.: used to configure sysprep
)
Add-Type -AssemblyName System.ServiceProcess -ErrorAction SilentlyContinue

function LogWriter($message) {
	$message = "$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
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
function RedirectPageFileTo($drive) {
	LogWriter("Redirecting pagefile to drive $($drive):")
	$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
	if ($CurrentPageFile -ne $null -and $CurrentPageFile.Name -ne "") {
		LogWriter("Existing pagefile name: '$($CurrentPageFile.Name)', max size: $($CurrentPageFile.MaximumSize)")
		if ($CurrentPageFile) {$CurrentPageFile.delete()}
		LogWriter("Pagefile deleted")
		$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
		if ($null -eq $CurrentPageFile) {
			LogWriter("Pagefile deletion successful")
		}
		else {
			LogWriter("Pagefile deletion failed")
		}
	}
	Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name = "$($drive):\pagefile.sys"; InitialSize = 0; MaximumSize = 0 }
	$CurrentPageFile = Get-WmiObject -Query 'select * from Win32_PageFileSetting'
	if ($null -eq $CurrentPageFile) {
		LogWriter("Pagefile not found")
	}
	else {
		LogWriter("New pagefile name: '$($CurrentPageFile.Name)', max size: $($CurrentPageFile.MaximumSize)")
	}
}
function RedirectPageFileToLocalStorageIfExist() {
	# configure page file on local storage if exist
	$pageFileDrive=""
	$disks = Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }
	foreach ($disk in $disks) { if ($disk.Name -ne 'C:\' -and $disk.Name -ne '' -and $disk.Name -ne $null -and $disk.Label -eq 'Temporary Storage') {
			$pageFileDrive=$disk.Name.Replace(":\","")
		}
	}
	if ($pageFileDrive -ne "") {
		LogWriter("Redirecting pagefile to local storage on $($pageFileDrive):")
		RedirectPageFileTo($pageFileDrive)
	}
}
function UnzipFile($zipfile, $outdir) {
	# Based on https://gist.github.com/nachivpn/3e53dd36120877d70aee
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$files = [System.IO.Compression.ZipFile]::OpenRead($zipfile)
	foreach ($entry in $files.Entries) {
		$targetPath = [System.IO.Path]::Combine($outdir, $entry.FullName)
		$directory = [System.IO.Path]::GetDirectoryName($targetPath)
       
		if (!(Test-Path $directory )) {
			New-Item -ItemType Directory -Path $directory | Out-Null 
		}
		if (!$targetPath.EndsWith("/")) {
			[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true);
		}
	}
}
function IsMsiFile($file) {
    if (!(Test-Path $file -PathType Leaf)) {
        return $false
    }
    try {
        $wi = New-Object -ComObject WindowsInstaller.Installer
        $db = $wi.OpenDatabase($file, 0)
        return $true
    } catch {
        return $false
    }
}
function DownloadFile($url, $outFile, $alternativeUrls) {
    $altUrls = @($url)
    $altIdx = -1
    $err = ""
    if ($alternativeUrls -ne $null -and $alternativeUrls -ne "") {
        $altUrls += $alternativeUrls.Split("|")
        $altIdx = $altUrls.Length
        for ($i=0; $i -le $altIdx-1; $i++) {
            $url=$altUrls[$i]
            try {
                DownloadFileIntern $url $outFile
                return
            } catch {
                $err += "$_  ---  "
                if ($i -lt $altIdx-1) {
                } else {
                    throw "DownloadFile: $err"
                }
            }
        }
    } else {
        DownloadFileIntern $url $outFile
    }
}
function DownloadFileIntern($url, $outFile) {
	$i = 4
	$ok = $false;
	$ignoreError = $false
    # Rename target file if exist
    Remove-Item -Path "$($outFile).itpc.bak" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $outFile) {
        Copy-Item -Path $outFile -Destination "$($outFile).itpc.bak" -ErrorAction SilentlyContinue
    }
    
	do {
		try {
			LogWriter("Try to download file from $url")
			(New-Object System.Net.WebClient).DownloadFile($url, $outFile)
			# if MSI file, validate if the file is validate
			if ([System.IO.Path]::GetExtension($outFile) -eq ".msi" -and (IsMsiFile $outFile) -eq $false) {
				throw "An MSI file was expected but the file is not a valid MSI file"
			}
			$ok = $true
		}
		catch {
			$i--;
			LogWriter("Download failed: $_")
			if ($i -le 0) {
                if (Test-Path -Path "$($outFile).itpc.bak") {
					Remove-Item -Path "$($outFile)" -Force -ErrorAction SilentlyContinue
                    Rename-Item -Path "$($outFile).itpc.bak" -NewName "$($outFile)"
					$ignoreError = $true
                }
				if ($ignoreError) {
                    LogWriter("Resuming and suppressing an exception while we still have an older file")
                    return
                } else {
                    throw
                }
			}
			LogWriter("Re-trying download after 5 seconds")
			Start-Sleep -Seconds 5
		}
	} while (!$ok)
    Remove-Item -Path "$($outFile).itpc.bak" -Force -ErrorAction SilentlyContinue
	LogWriter("Download done")
}
function CopyFileWithRetry($source, $destination) {
	$i = 5
	$ok = $false;
	do {
		try {
			Copy-Item $source -Destination $destination -ErrorAction Stop
			$ok = $true
		}
		catch {
			$i--;
			if ($i -le 0) {
				LogWriter("Copy failed: $_")
				return
			}
			LogWriter("Re-trying copy after 3 seconds")
			Start-Sleep -Seconds 3
		}
	} while (!$ok)
	LogWriter("File copied successfully")
}
function RemoveHiddenIfExist($file) {
    try {
        if (Test-Path -Path $file) {
            LogWriter("RemoveHiddenIfExist: File exist: $($file)")
            $fileItem=Get-Item $file -Force
            if (($fileItem.Attributes -band  [System.IO.FileAttributes]::Hidden) -eq [System.IO.FileAttributes]::Hidden) {
                LogWriter("RemoveHiddenIfExist: Removing hidden flag from file $($fileItem.Name)")
                $fileItem.Attributes = $fileItem.Attributes -band -bnot [System.IO.FileAttributes]::Hidden
            } else {
                LogWriter("RemoveHiddenIfExist: File is not hidden: $($fileItem.Name)")
            }
        }
    } catch {
        LogWriter("RemoveHiddenIfExist failed: $_")
    }
}
function ExecuteFileAndAwait($file) {
    # Supports the execution of ps1, cmd, bat, and exe files
    try {
        $filePath = [System.IO.Path]::GetDirectoryName($file)
        $fileExtension = [System.IO.Path]::GetExtension($file)
        $fileName = [System.IO.Path]::GetFileName($file)
        if (Test-Path -Path "$file") {
            LogWriter("ExecuteFileAndAwait: Starting $file")
            if ($fileExtension -like ".bat" -or $fileExtension -like ".cmd") {
                Start-Process -FilePath "$env:windir\system32\cmd.exe" -ArgumentList "/c $fileName" -WorkingDirectory "$filePath" -Wait -PassThru
                LogWriter("ExecuteFileAndAwait: Finished $file")
            } elseif ($fileExtension -like ".exe") {
                Start-Process -FilePath "$file" -WorkingDirectory "$filePath" -Wait -PassThru
                LogWriter("ExecuteFileAndAwait: Finished $file")
            } elseif ($fileExtension -like ".ps1") {
                . "$file"
                LogWriter("ExecuteFileAndAwait: Finished $file")
            } else {
                LogWriter("ExecuteFileAndAwait: Unknown file format: $fileExtension")
            }
        }

    } catch {
        LogWriter("ExecuteFileAndAwait: $_")
    }
}
function WaitForServiceExist ($serviceName,$timeOutSeconds,$repeat) {
	$retryCount = 0
	while ( -not (Get-Service $serviceName -ErrorAction SilentlyContinue)) {
		$retry = ($retryCount -lt $repeat)
		if ($retry) { 
			LogWriter("Service $serviceName was not found - Retrying again in $timeOutSeconds seconds, this will be retry $retryCount")
		} 
		else {
			LogWriter("Service $serviceName was not found - Retry limit exceeded: $serviceName didn't become available after $retry retries")
			return $false
		}            
		$retryCount++
		Start-Sleep -Seconds $timeOutSeconds
	}
    return $true
}
function StoreServiceConfiguration($serviceName) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -ne $null)
    {
        LogWriter("Service exist with start type: $($service.StartType) - storing state to registry and set start type to disabled and service is stopped - will be reverted on the next rollout")
        New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "Service.$($serviceName)" -Value ([int]$service.StartType) -force
        Set-Service -Name $serviceName -StartupType ([System.ServiceProcess.ServiceStartMode]::Disabled)
        Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
    } else {Remove-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "Service.$($serviceName)" -Force -ErrorAction SilentlyContinue}
}
function StopAndRemoveSchedTask($taskName) {
	$task = Get-ScheduledTask -TaskName  $taskName -ErrorAction SilentlyContinue
	if ($task -ne $null) {
		LogWriter("Stopping and removing task $taskName")
		Stop-ScheduledTask -TaskName $taskName -ErrorAction Ignore
		Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
	}
}
function AddRegistyKey($key) {
	if (-not (Test-Path $key)) {
		New-Item -Path $key -Force -ErrorAction SilentlyContinue
	}
}
function ApplyOsSettings() {
	LogWriter("Applying host configuration if configured: Start")
	try {
		$osSettingsObj = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parameters)) | ConvertFrom-Json
		if ($osSettingsObj.FrxProfile.Enabled) {
			LogWriter("Configuring FSLogix profile settings")

			$regPath="HKLM:\SOFTWARE\FSLogix\Profiles"
			AddRegistyKey $regPath
			if ($osSettingsObj.FrxProfile.VHDLocations -and $osSettingsObj.FrxProfile.VHDLocations -ne "") {
				LogWriter("Configuring FSLogix profile settings: VHDLocation = $($osSettingsObj.FrxProfile.VHDLocations)")
				New-ItemProperty -Path $regPath -Name "VHDLocations" -Value $osSettingsObj.FrxProfile.VHDLocations -force
			}
			if ($osSettingsObj.FrxProfile.RedirXMLSourceFolder -and $osSettingsObj.FrxProfile.RedirXMLSourceFolder -ne "") {
				LogWriter("Configuring FSLogix profile settings: RedirXMLSourceFolder = $($osSettingsObj.FrxProfile.RedirXMLSourceFolder)")
				New-ItemProperty -Path $regPath -Name "RedirXMLSourceFolder" -Value $osSettingsObj.FrxProfile.RedirXMLSourceFolder -force
			}
			LogWriter("Configuring FSLogix profile settings: Enabled = True")
			New-ItemProperty -Path $regPath -Name "Enabled" -Value 1 -force
			LogWriter("Configuring FSLogix profile settings: DeleteLocalProfileWhenVHDShouldApply = $($osSettingsObj.FrxProfile.DeleteLocalProfileWhenVHDShouldApply)")
			New-ItemProperty -Path $regPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value ([int]$osSettingsObj.FrxProfile.DeleteLocalProfileWhenVHDShouldApply) -force
			LogWriter("Configuring FSLogix profile settings: FlipFlopProfileDirectoryName = $($osSettingsObj.FrxProfile.FlipFlopProfileDirectoryName)")
			New-ItemProperty -Path $regPath -Name "FlipFlopProfileDirectoryName" -Value ([int]$osSettingsObj.FrxProfile.FlipFlopProfileDirectoryName) -force
			LogWriter("Configuring FSLogix profile settings: IsDynamic = $($osSettingsObj.FrxProfile.IsDynamic)")
			New-ItemProperty -Path $regPath -Name "IsDynamic" -Value ([int]$osSettingsObj.FrxProfile.IsDynamic) -force
			LogWriter("Configuring FSLogix profile settings: KeepLocalDir = $($osSettingsObj.FrxProfile.KeepLocalDir)")
			New-ItemProperty -Path $regPath -Name "KeepLocalDir" -Value ([int]$osSettingsObj.FrxProfile.KeepLocalDir) -force
			LogWriter("Configuring FSLogix profile settings: SizeInMBs = $($osSettingsObj.FrxProfile.SizeInMBs)")
			New-ItemProperty -Path $regPath -Name "SizeInMBs" -Value $osSettingsObj.FrxProfile.SizeInMBs -force
			LogWriter("Configuring FSLogix profile settings: VolumeType = $($osSettingsObj.FrxProfile.VolumeType)")
			New-ItemProperty -Path $regPath -Name "VolumeType" -Value $osSettingsObj.FrxProfile.VolumeType -force
			if ($osSettingsObj.FrxProfile.EntraIdKerberos) {
				LogWriter("Configuring FSLogix profile settings: EntraIdKerberos")
				AddRegistyKey "HKLM:\Software\Policies\Microsoft\AzureADAccount"
		        New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\AzureADAccount" -Name "LoadCredKeyFromProfile" -Value 1 -force
				AddRegistyKey "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
		        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Name "CloudKerberosTicketRetrievalEnabled" -Value 1 -force
			}
			if ($osSettingsObj.FrxProfile.UpdateBinaries) {
				LogWriter("Configuring FSLogix profile settings: Update Binaries from Microsoft website")
				try {
		            Remove-Item -Path "$($env:temp)\FSLogixInstall" -Recurse -Force -ErrorAction SilentlyContinue
		            DownloadFile "https://aka.ms/fslogix_download" "$($env:temp)\FSLogix.zip"
		            UnzipFile "$($env:temp)\FSLogix.zip" "$($env:temp)\FSLogixInstall"
		            Start-Process -FilePath "$($env:temp)\FSLogixInstall\*\x64\Release\FSLogixAppsSetup.exe" -ArgumentList "/install /quiet /norestart"
				} catch {
					LogWriter("Configuring FSLogix profile settings: Update Binaries from Microsoft website failed: $_")
				}
			}
		}
		if ($osSettingsObj.Os.Enabled) {
			LogWriter("Configuring OS settings")
			if ($osSettingsObj.Os.AllowPrinterDriver) {
				LogWriter("Configuring OS profile settings: Allow users to install printer driver = $($osSettingsObj.Os.AllowPrinterDriver)")
		        AddRegistyKey "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint\AddIns"
		        New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -Name "RestrictDriverInstallationToAdministrators " -Value 0 -force
		        New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -Name "Restricted " -Value 0 -force
		        AddRegistyKey "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverInstall\Restrictions\AllowUserDeviceClasses\AddIns"
		        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverInstall\Restrictions\AllowUserDeviceClasses" -Name "1 " -Value "{4d36e979-e325-11ce-bfc1-08002be10318}" -force
		        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverInstall\Restrictions\AllowUserDeviceClasses" -Name "2 " -Value "{4658ee7e-f050-11d1-b6bd-00c04fa372a7}" -force
		        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverInstall\Restrictions\AllowUserDeviceClasses" -Name "3 " -Value "{4d36e973-e325-11ce-bfc1-08002be10318}" -force
			}
		}
		if ($osSettingsObj.Rds.Enabled) {
			LogWriter("Configuring RDS settings")
			$regPath="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
			AddRegistyKey $regPath
			LogWriter("Configuring RDS settings: fEnableTimeZoneRedirection = $($osSettingsObj.Rds.fEnableTimeZoneRedirection)")
			New-ItemProperty -Path $regPath -Name "fEnableTimeZoneRedirection" -Value ([int]$osSettingsObj.Rds.fEnableTimeZoneRedirection) -force
			LogWriter("Configuring RDS settings: fForceClientLptDef = $($osSettingsObj.Rds.fForceClientLptDef)")
			New-ItemProperty -Path $regPath -Name "fForceClientLptDef" -Value ([int]$osSettingsObj.Rds.fForceClientLptDef) -force
			LogWriter("Configuring RDS settings: HEVCHardwareEncodePreferred = $($osSettingsObj.Rds.HEVCHardwareEncodePreferred)")
			New-ItemProperty -Path $regPath -Name "HEVCHardwareEncodePreferred" -Value ([int]$osSettingsObj.Rds.HEVCHardwareEncodePreferred) -force
			LogWriter("Configuring RDS settings: AVC444ModePreferred = $($osSettingsObj.Rds.AVC444ModePreferred)")
			New-ItemProperty -Path $regPath -Name "AVC444ModePreferred" -Value ([int]$osSettingsObj.Rds.AVC444ModePreferred) -force
			LogWriter("Configuring RDS settings: bEnumerateHWBeforeSW = $($osSettingsObj.Rds.bEnumerateHWBeforeSW)")
			New-ItemProperty -Path $regPath -Name "bEnumerateHWBeforeSW" -Value ([int]$osSettingsObj.Rds.bEnumerateHWBeforeSW) -force
			LogWriter("Configuring RDS settings: fEnableRemoteFXAdvancedRemoteApp = $($osSettingsObj.Rds.fEnableRemoteFXAdvancedRemoteApp)")
			New-ItemProperty -Path $regPath -Name "fEnableRemoteFXAdvancedRemoteApp" -Value ([int]$osSettingsObj.Rds.fEnableRemoteFXAdvancedRemoteApp) -force
			LogWriter("Configuring RDS settings: AVCHardwareEncodePreferred = $($osSettingsObj.Rds.AVCHardwareEncodePreferred)")
			New-ItemProperty -Path $regPath -Name "AVCHardwareEncodePreferred" -Value $osSettingsObj.Rds.AVCHardwareEncodePreferred -force
			LogWriter("Configuring RDS settings: MaxIdleTime = $($osSettingsObj.Rds.MaxIdleTime)")
			if ($osSettingsObj.Rds.MaxIdleTime -lt 0) {
				Remove-ItemProperty -Path $regPath -Name "MaxIdleTime" -force -ErrorAction SilentlyContinue
			} else {
				New-ItemProperty -Path $regPath -Name "MaxIdleTime" -Value (60000*$($osSettingsObj.Rds.MaxIdleTime)) -PropertyType DWord -force
			}
			LogWriter("Configuring RDS settings: RemoteAppLogoffTimeLimit = $($osSettingsObj.Rds.RemoteAppLogoffTimeLimit)")
			if ($osSettingsObj.Rds.RemoteAppLogoffTimeLimit -lt 0) {
				Remove-ItemProperty -Path $regPath -Name "RemoteAppLogoffTimeLimit" -force -ErrorAction SilentlyContinue
			} else {
				New-ItemProperty -Path $regPath -Name "RemoteAppLogoffTimeLimit" -Value (60000*$($osSettingsObj.Rds.RemoteAppLogoffTimeLimit)) -PropertyType DWord -force
			}
			$regPath="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
			AddRegistyKey $regPath
			LogWriter("Configuring RDS settings: fUseUdpPortRedirector = $($osSettingsObj.Rds.fUseUdpPortRedirector)")
			New-ItemProperty -Path $regPath -Name "fUseUdpPortRedirector" -Value ([int]$osSettingsObj.Rds.fUseUdpPortRedirector) -force
			if ($osSettingsObj.Rds.fUseUdpPortRedirector) {
				LogWriter("Configuring RDS settings: UdpPortNumber = 3390")
				New-ItemProperty -Path $regPath -Name "UdpPortNumber" -Value 3390 -force
				LogWriter("Configuring RDS settings: Configuring Windows Firewall")
				New-NetFirewallRule -DisplayName "Remote Desktop - Shortpath (UDP)"  -Action Allow -Description "Inbound rule for the Remote Desktop service to allow RDP traffic on UDP 3390" -Group "@FirewallAPI.dll,-28752" -Name 'RemoteDesktop-RDP-Shortpath-UDP'  -PolicyStore PersistentStore -Profile Any -Service TermService -Protocol udp -LocalPort 3390 -Program "%SystemRoot%\system32\svchost.exe" -Enabled:True -ErrorAction SilentlyContinue
			}
		}
		if ($osSettingsObj.Teams.Enabled) {
			LogWriter("Optimizing Teams")
			AddRegistyKey "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy"
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy" -Name "ShareClientDesktop" -Value 1 -force
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy" -Name "DisableRAILScreensharing" -Value 0 -force
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\AddIns\WebRTC Redirector\Policy" -Name "DisableRAILAppSharing" -Value 0 -force
		}
	} catch {
		LogWriter("Applying host configuration failed: $_")
	}
	LogWriter("Applying host configuration if configured: End")
}
function SysprepPreClean() {
	# DISM cleanup (only if forced)
	if (Test-Path "$env:windir\system32\Dism.exe") {
		LogWriter("DISM cleanup - Start")
		Start-Process -FilePath "$env:windir\system32\Dism.exe" -Wait -ArgumentList "/online /cleanup-image /startcomponentcleanup /resetbase" -ErrorAction SilentlyContinue
		LogWriter("DISM cleanup - Done")
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
function GetAccessToFolder($accessPath) {
	# Get access to folders and files
	try {
        LogWriter("Taking ownership and resetting permissions in subfolders and files of $accessPath")
        $accessPath=$accessPath.ToLower();
        try {
	        $accessPathItem = Get-Item $accessPath.Replace("c:\", "\\localhost\\c$\") -ErrorAction Stop
        } catch {
            LogWriter("Using native path without using \\localhost")
	        $accessPathItem = Get-Item $accessPath -ErrorAction Stop
        }
		$acl = $accessPathItem.GetAccessControl()
		$acl.SetOwner((New-Object System.Security.Principal.NTAccount("System")))
        try {
		    $accessPathItem.SetAccessControl($acl)
        } catch {
            LogWriter("Unable to take ownership to path with PowerShell")
        }
        try {
		    $oea=$ErrorActionPreference
			$ErrorActionPreference = 'Stop'
            takeown /R /F "$accessPath"
        } catch {
            LogWriter("Unable to take ownership with takeown.exe")
        }		
		$ErrorActionPreference=$oea
        $acl = $accessPathItem.GetAccessControl()
		$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl",([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit), [System.Security.AccessControl.PropagationFlags]::InheritOnly, "Allow")
		$acl.AddAccessRule($aclSystemFull)
		$aclSystemFull = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
		$acl.AddAccessRule($aclSystemFull)
		$accessPathItem.SetAccessControl($acl)
        
        LogWriter("Reseting inheritance of permissions")
        Get-ChildItem -Path $accessPathItem -Recurse | foreach {
            $acl = get-acl $_.FullName
            $acl.SetAccessRuleProtection($false,$false)
            Set-Acl -Path $_.FullName -AclObject $acl -ErrorAction SilentlyContinue
   
        }
	} catch {
		LogWriter("Getting access for system to path $accessPath failed: $_")
	}
}
function RunSysprep($parameters) {	
	# Run sysprep in another task to let the runcommand call end and monitor the sysprep log file in parallel
	Start-Process -FilePath PowerShell.exe -WorkingDirectory $LocalConfig -ArgumentList "-ExecutionPolicy Bypass -File `"$($LocalConfig)\ITPC-WVD-Image-Processing.ps1`" -Mode RunSysprep -parameters `"$($parameters)`""
}
function RunSysprepInternal($parameters) {
	LogWriter("Starting sysprep to generalize session host")
	$sysprepErrorLogFile = "$env:windir\System32\Sysprep\Panther\setuperr.log"

	# Stopping windows update service during the imaging process
	LogWriter("Stopping windows update service during the imaging process")
	Stop-Service wuauserv -Force -NoWait -ErrorAction SilentlyContinue

	# Get access to the log files
	$sysPrepLogPath = "$env:windir\System32\Sysprep\Panther"
	GetAccessToFolder $sysPrepLogPath

	$errorReason = ""
	$restrartSysprepOnce = 6
	do {
		Remove-Item -Path $sysprepErrorLogFile -Force -ErrorAction Ignore
		LogWriter("Resetting sysprep state")
		Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Sysprep" -Name "SysprepCorrupt" -ErrorAction Ignore
		New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "State" -Value 2 -force
		New-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -force
		AddRegistyKey "HKLM:\Software\Microsoft\DesiredStateConfiguration"
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DesiredStateConfiguration" -Name "AgentId" -Value "" -force  -ErrorAction Ignore

		if ($errorReason -ne "") {
			LogWriter("Patch Generalize.xml to workaround $errorReason")
			# Patch Generalize.xml
			try {
				$sysPrepActionFile = "Generalize.xml"
				$sysPrepActionPath = "$env:windir\System32\Sysprep\ActionFiles"

				# Get access to sysprep action files
				GetAccessToFolder $sysPrepActionPath

				[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
				$xml.SelectNodes("//assemblyIdentity") | ForEach-Object {
					if ($_.name -match $errorReason) { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
				}
				$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
				Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old.*" -Force -ErrorAction Ignore
				Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old.$((Get-Date).ToString("yyyy-MM-dd_HH-mm-ss"))"
				Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
				LogWriter("Modifying sysprep Generalize - Done")
			} catch {
				LogWriter("Modifying sysprep Generalize - Failed: $_")
			}
		}

		# Workaround for a hidden system file
		RemoveHiddenIfExist "$env:windir\system32\VMAgentDisabler.dll"
		LogWriter("Starting sysprep executable")
		$proc = Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList $parameters -PassThru

		$restrartSysprepOnce--

		# Wait for sysprep shutdown and monitor logfile
		$again = $true
		do {
			LogWriter("Waiting for sysprep executable")
			Start-Sleep -Seconds 5
			if ((Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) -eq $null) {
				LogWriter("Sysprep executable finished")
				$again = $false
				#$restrartSysprepOnce = 0
			}
			$sysprepErrorLog = Get-Content -Path $sysprepErrorLogFile -ErrorAction SilentlyContinue
			if ($sysprepErrorLog) {
				$hasError = $false
				$errorReason = ""
				$errorReasonFull = ""
				$sysprepErrorLog | foreach {
					# check for error
					if ($_ -like "*, Error *") {
						if ($_ -like "*ExecuteInternal*") {
							$pattern = "(?<=Error in executing action for\s)(.*?)(?=;)"
							$errorReason = Select-String -InputObject $_ -Pattern $pattern -AllMatches | Foreach-Object { $_.Matches.Value }
							if ($restrartSysprepOnce -eq 0) {
								LogWriter("Sysprep failed: $_")
								throw "Sysprep failed: $_"
							}
						}
						if ($_.IndexOf(", Error      [") -gt -1) {
							$again = $false
							$hasError = $true
						}
					}
				}
				if ($hasError -and $restrartSysprepOnce -gt 0) {
					# Do one time a force clean-up for sysprep
					LogWriter("Convincing sysprep to sysprep the system. Last error: $errorReason")
					Start-Sleep -Seconds 5
					try { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue } catch {}
					SysprepPreClean
				} 
			}
			if ($again -eq $false -and $hasError -eq $false) {
				$restrartSysprepOnce = 0
			}
		} while ($again)
	} while ($restrartSysprepOnce -gt 0)
	LogWriter("Finishing RunSysprep")
}

# Define static variables
$LocalConfig = "C:\ITPC-WVD-PostCustomizing"
$unattend = "PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0ndXRmLTgnPz48dW5hdHRlbmQgeG1sbnM9InVybjpzY2hlbWFzLW1pY3Jvc29mdC1jb206dW5hdHRlbmQiPjxzZXR0aW5ncyBwYXNzPSJvb2JlU3lzdGVtIj48Y29tcG9uZW50IG5hbWU9Ik1pY3Jvc29mdC1XaW5kb3dzLVNoZWxsLVNldHVwIiBwcm9jZXNzb3JBcmNoaXRlY3R1cmU9ImFtZDY0IiBwdWJsaWNLZXlUb2tlbj0iMzFiZjM4NTZhZDM2NGUzNSIgbGFuZ3VhZ2U9Im5ldXRyYWwiIHZlcnNpb25TY29wZT0ibm9uU3hTIiB4bWxuczp3Y209Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vV01JQ29uZmlnLzIwMDIvU3RhdGUiIHhtbG5zOnhzaT0iaHR0cDovL3d3dy53My5vcmcvMjAwMS9YTUxTY2hlbWEtaW5zdGFuY2UiPjxPT0JFPjxTa2lwTWFjaGluZU9PQkU+dHJ1ZTwvU2tpcE1hY2hpbmVPT0JFPjxTa2lwVXNlck9PQkU+dHJ1ZTwvU2tpcFVzZXJPT0JFPjwvT09CRT48L2NvbXBvbmVudD48L3NldHRpbmdzPjwvdW5hdHRlbmQ+"

# Define logfile
$LogFile = $LogDir + "\AVD.Customizing.log"

# Main
LogWriter("Starting ITPC-WVD-Image-Processing in mode $mode")
AddRegistyKey "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime"

# Generating variables from Base64-coding
if ($LocalAdminName64) { $LocalAdminName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminName64)) }
if ($LocalAdminPassword64) { $LocalAdminPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LocalAdminPassword64)) }
if ($DomainJoinUserName64) { $DomainJoinUserName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserName64)) }
if ($DomainJoinUserPassword64) { $DomainJoinUserPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainJoinUserPassword64)) }
if ($AltAvdAgentDownloadUrl64) { $AltAvdAgentDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdAgentDownloadUrl64)) }
if ($AltAvdBootloaderDownloadUrl64) { $AltAvdBootloaderDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdBootloaderDownloadUrl64)) }

# check for the existend of the helper scripts
if ((Test-Path ($LocalConfig + "\ITPC-WVD-Image-Processing.ps1")) -eq $false) {
	# Create local directory for script(s) and copy files (including the RD agent and boot loader - rename it to the specified name)
	LogWriter("Copy files to local session host or downloading files from Microsoft")
	New-Item $LocalConfig -ItemType Directory -ErrorAction Ignore
	try { (Get-Item $LocalConfig -ErrorAction Ignore).attributes = "Hidden" } catch {}

	if ((Test-Path ("${PSScriptRoot}\ITPC-WVD-Image-Processing.ps1")) -eq $false) {
		LogWriter("Creating ITPC-WVD-Image-Processing.ps1 from invocation")
		if ($CallScript -and $CallScript -ne "") {
			Copy-Item $CallScript -Destination ($LocalConfig + "\ITPC-WVD-Image-Processing.ps1") -Container:$false
		} else {
			Copy-Item "$($MyInvocation.InvocationName)" -Destination ($LocalConfig + "\ITPC-WVD-Image-Processing.ps1") -Container:$false
		}
	}
	else {
		LogWriter("Creating ITPC-WVD-Image-Processing.ps1 from PSScriptRoot")
		Copy-Item "${PSScriptRoot}\ITPC-WVD-Image-Processing.ps1" -Destination ($LocalConfig + "\") -ErrorAction SilentlyContinue
	}
}
if ($ComputerNewname -eq "" -or $DownloadNewestAgent -eq "1") {
	if ((Test-Path ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
		if ((Test-Path ($ScriptRoot + "\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
			LogWriter("Downloading RDAgent")
			DownloadFile "https://go.microsoft.com/fwlink/?linkid=2310011" ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi") $AltAvdAgentDownloadUrl
			# DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi") $AltAvdAgentDownloadUrl
		}
		else { Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($LocalConfig + "\") }
	}
	if ((Test-Path ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
		if ((Test-Path ($ScriptRoot + "\Microsoft.RDInfra.RDAgentBootLoader.msi ")) -eq $false -or $DownloadNewestAgent -eq "1") {
			LogWriter("Downloading RDBootloader")
			DownloadFile "https://go.microsoft.com/fwlink/?linkid=2311028" ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi") $AltAvdBootloaderDownloadUrl
			# DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi") $AltAvdBootloaderDownloadUrl
		}
		else { Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($LocalConfig + "\") }
	}
}

# updating local script (from maybe an older version from the last image process)
if ("$($MyInvocation.MyCommand.Path)" -ne ($LocalConfig + "\ITPC-WVD-Image-Processing.ps1")) {
	LogWriter("Updating ITPC-WVD-Image-Processing.ps1")
	CopyFileWithRetry "$($MyInvocation.MyCommand.Path)" ($LocalConfig + "\ITPC-WVD-Image-Processing.ps1")
}

# check, if secure boot is enabled (used by the snapshot workaround)
$isSecureBoot = $false
try {
	$isSecureBoot = Confirm-SecureBootUEFI
}
catch {}

# try to get windows full version to do some workarounds
$is1122H2 = $false
try {
	$ci = Get-ComputerInfo
	if ($ci.OsName -match "Windows 11" -and $ci.OSDisplayVersion -match "22h2") {
		$is1122H2 = $true
		LogWriter("Windows 11 22H2 detected")
	}
}
catch {}

# Start script by mode
if ($mode -eq "Generalize") {
	LogWriter("Check for PreImageCustomizing scripts")
	ExecuteFileAndAwait "$env:windir\Temp\PreImageCustomizing.exe"
	ExecuteFileAndAwait "$env:windir\Temp\PreImageCustomizing.cmd"
	ExecuteFileAndAwait "$env:windir\Temp\PreImageCustomizing.bat"
	ExecuteFileAndAwait "$env:windir\Temp\PreImageCustomizing.ps1"

	LogWriter("Removing existing Remote Desktop Agent Boot Loaders")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agents")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore
	LogWriter("Removing existing SxS Network Stack installations")
	Uninstall-Package -Name "Remote Desktop Services SxS Network Stack" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Geneva Agents")
	Get-Package | Where-Object {$_.Name -like "Remote Desktop Services Infrastructure Geneva Agent *"} | Uninstall-Package -AllVersions -Force -ErrorAction SilentlyContinue 

	LogWriter("Disabling ITPC-LogAnalyticAgent and MySmartScale if exist") 
	Disable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
	Disable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore

	LogWriter("Removing schedule tasks maybe created by this script on an existing host")
	StopAndRemoveSchedTask "ITPC-AVD-CleanFirstStart-Helper"
	StopAndRemoveSchedTask "ITPC-AVD-Enroll-To-Intune"
	StopAndRemoveSchedTask "ITPC-AVD-RDAgentBootloader-Helper"
	StopAndRemoveSchedTask "ITPC-AVD-RDAgentMonitoring-Monitor"
	StopAndRemoveSchedTask "ITPC-AVD-RDAgentBootloader-Monitor-1"
	StopAndRemoveSchedTask "ITPC-AVD-RDAgentBootloader-Monitor-2"

	LogWriter("Prevent removing language packs")
	AddRegistyKey "HKLM:\Software\Policies\Microsoft\Control Panel\International"
	New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -force

	LogWriter("Cleaning up reliability messages")
	$key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability"
	Remove-ItemProperty -Path $key -Name "DirtyShutdown" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "DirtyShutdownTime" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "LastAliveStamp" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "TimeStampInterval" -ErrorAction Ignore

	LogWriter("Saving BitLocker service state for re-deploy (BDESVC)")
	StoreServiceConfiguration("BDESVC")

	LogWriter("Saving MECM service state for re-deploy (ccmexec)")
	StoreServiceConfiguration("ccmexec")

	# Disable Bitlocker, if needed
	try {
		manage-bde -autounlock -ClearAllKeys C:
		Disable-BitLocker -MountPoint C: -ErrorAction Stop
		LogWriter("Disable Bitlocker")
		do {
			$isBitLocker=(Get-BitLockerVolume -MountPoint C: -ErrorAction Stop).EncryptionPercentage
			LogWriter("Wait for encryption of drive C:")
			if ($isBitLocker -ne 0) {Start-Sleep -Seconds 5}
		} while ($isBitLocker -ne 0)
	} catch {}

	LogWriter("Cleaning up some Defender For Endpoint properties - the master should not be onboarded")
	Remove-Item -Path "C:\ProgramData\Microsoft\Windows Defender Advanced Threat Protection\Cyber\*.*" -Recurse -Force -ErrorAction Ignore
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection" -Name "senseGuid" -ErrorAction Ignore
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection" -Name "7DC0B629-D7F6-4DB3-9BF7-64D5AAF50F1A" -ErrorAction Ignore
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\48A68F11-7A16-4180-B32C-7F974C7BD783" -Name "7DC0B629-D7F6-4DB3-9BF7-64D5AAF50F1A" -ErrorAction Ignore

	# Triggering dotnet to execute queued items
	$dotnetRoot = "$env:windir\Microsoft.NET\Framework"
	Get-ChildItem -Path $dotnetRoot -Directory | foreach {
		if (Test-Path "$($_.FullName)\ngen.exe") {
			LogWriter("Triggering dotnet to execute queued items in: $($_.FullName)")
			Start-Process -FilePath "$($_.FullName)\ngen.exe" -Wait -ArgumentList "ExecuteQueuedItems" -ErrorAction SilentlyContinue
		}
	}

	# Read property from registry (force imaging, like dism)
	$force = $StrongGeneralize -eq "1"
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Force") {
		$force = $true
	}

	# SysprepPreClean: DSIM and reserved storage
	if ($force) {
		SysprepPreClean	
	}
	
	# Removing the state of an olde AAD Join
	LogWriter("Cleaning up previous AADLoginExtension / AAD join")
	Remove-Item -Path "c:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState\Microsoft.Azure.ActiveDirectory.AADLoginForWindows_*" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Azure\CurrentVersion\AADLoginForWindowsExtension" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin"  -Recurse -Force -ErrorAction Ignore
	$AadCerts = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -match "CN=MS-Organization-P2P-Access*" -or $_.Issuer -match "CN=Microsoft Intune MDM Device CA" -or $_.Issuer -match "CN=MS-Organization-Access" -or $_.Issuer -match "DC=Windows Azure CRP Certificate Generator"}
	if ($AadCerts -ne $null) {
		$AadCerts | ForEach-Object {
			$cn = $_.Subject.Split(",")

			LogWriter("Found probaly a AAD/Intune certificate with name: $cn")
			Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match "$($cn)*" } | ForEach-Object {
				LogWriter("Deleting certificate from image with subject: $($_.Subject)")
				Remove-Item -Path $_.PSPath
			}    
		}
	}
	# Removing an old intune configuration to avoid an uninstall of installed applications
	LogWriter("Removing intune configuration")
	if ((Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue) -ne $null) {
		Stop-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue -Force
	}
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\C4CAE00E-51B1-4736-A39A-D59275FD6816\DMClient\MS DM Server" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot" -Recurse -Force -ErrorAction Ignore
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\C4CAE00E-51B1-4736-A39A-D59275FD6816" -Recurse -Force -ErrorAction Ignore
	Uninstall-Package -Name "Microsoft Intune Management Extension" -AllVersions -Force -ErrorAction SilentlyContinue 

	# Get access to sysprep action files
	$sysPrepActionPath = "$env:windir\System32\Sysprep\ActionFiles"
	GetAccessToFolder $sysPrepActionPath
	
	# Patch Generalize.xml
	$sysPrepActionFile = "Generalize.xml"
	[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
	$xml.SelectNodes("//sysprepModule") | ForEach-Object {
		if ($_.moduleName -match "AppxSysprep.dll") { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
		if ($_.moduleName -match "spwmp.dll") { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
		if ($_.moduleName -match "wuaueng.dll") { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
	}
	$xml.Save("$sysPrepActionPath\$sysPrepActionFile.new")
	Remove-Item "$sysPrepActionPath\$sysPrepActionFile.old.*" -Force -ErrorAction Ignore
	Move-Item "$sysPrepActionPath\$sysPrepActionFile" "$sysPrepActionPath\$sysPrepActionFile.old.$((Get-Date).ToString("yyyy-MM-dd_HH-mm-ss"))"
	Move-Item "$sysPrepActionPath\$sysPrepActionFile.new" "$sysPrepActionPath\$sysPrepActionFile"
	LogWriter("Modifying sysprep Generalize - Done")
	
	# Patch Specialize.xml for Windows 11 22H2 as workaround
	if ($is1122H2) {
		LogWriter("Modifying sysprep Specialize to avoid issues with Windows 11 22H2")
		$sysPrepActionFile = "Specialize.xml"
		[xml]$xml = Get-Content -Path "$sysPrepActionPath\$sysPrepActionFile"
		$xml.SelectNodes("//sysprepModule") | ForEach-Object {
			if ($_.methodName -eq "CryptoSysPrep_Specialize") { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
		}
		$xml.SelectNodes("//sysprepModule") | ForEach-Object {
			if ($_.methodName -eq "CryptoSysPrep_Specialize") { $_.ParentNode.ParentNode.RemoveChild($_.ParentNode) | Out-Null }
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
	AddRegistyKey "HKLM:\Software\Microsoft\DesiredStateConfiguration"
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DesiredStateConfiguration" -Name "AgentId" -Value "" -force  -ErrorAction Ignore

	LogWriter("Saving time zone info for re-deploy")
	$timeZone = (Get-TimeZone).Id
	LogWriter("Current time zone is: " + $timeZone)
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force

	LogWriter("Removing existing Azure Monitoring Certificates and configuration")
	Get-ChildItem "Cert:\LocalMachine\Microsoft Monitoring Agent" -ErrorAction Ignore | Remove-Item
	LogWriter("Uninstalling Monitoring Agent")
	Uninstall-Package -Name "Microsoft Monitoring Agent" -AllVersions -Force  -ErrorAction Ignore
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\AzureMonitorAgent\Secrets" -Name "PersistenceKeyCreated" -ErrorAction Ignore


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
	$modifyDrives = $false
	$disks = Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }
	foreach ($disk in $disks) { if ($disk.Name -ne 'D:\' -and $disk.Label -eq 'Temporary Storage') { $modifyDrives = $true } }
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
		RedirectPageFileTo("c")
	}

	LogWriter("Preparing image to do one retry if the rollout of the VM failes (ADMINISTRATOR: Error Handler)")
	$patchFile="$($env:WinDir)\OEM\ErrorHandler.cmd"
	if (Test-Path -Path $patchFile) {
		try {
		LogWriter("Removing the old trigger file")
		Remove-Item -Path "$($env:WinDir)\OEM\DoOnce.txt" -Force -ErrorAction SilentlyContinue	
		LogWriter ("Checking file $patchFile")
		if (-not (Get-Content $patchFile | Select-String -Pattern "ITPC")) {
			LogWriter("Patching file")

			$PatchContent = @(
			"::ITPC - Patch",
			"set FileTrigger=%windir%\OEM\DoOnce.txt",
			"if not exist `"%FileTrigger%`" (",
			"    ECHO ErrorHandler.cmd FILETRIGGER >> %windir%\Panther\WaSetup.log",
			"    ECHO ErrorHandler.cmd FILETRIGGER >> %FileTrigger%",
			"    reg delete `"HKEY_LOCAL_MACHINE\SYSTEM\Setup\SetupCl`" /f",
			"    EXIT",
			") "
			)
			Set-ItemProperty -Path $patchFile -Name IsReadOnly -Value $false
			($PatchContent+(Get-Content $patchFile)) | Set-Content $patchFile
			Set-ItemProperty -Path $patchFile -Name IsReadOnly -Value $true
		}
		} catch {
			LogWriter("Error patching file: $_")
		}
	}
	
	LogWriter("Preparing sysprep to generalize session host")
	if ([System.Environment]::OSVersion.Version.Major -le 6) {
		#Windows 7
		LogWriter("Enabling RDP8 on Windows 7")
		AddRegistyKey "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
		New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fServerEnableRDP8" -Value 1 -force
		RunSysprep "/generalize /oobe /shutdown"
		#Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown"
	}
	else {
		if ($isSecureBoot) {
			LogWriter("Secure boot is enabled")
			write-output([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($unattend))) | Out-File "$LocalConfig\unattend.xml" -Encoding ASCII
			# write-output([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($unattend))) | Out-File "$env:windir\panther\unattend.xml" -Encoding ASCII
			RunSysprep 	"/generalize /oobe /shutdown /mode:vm /unattend:$LocalConfig\unattend.xml"
		}
		else {
			RunSysprep "/generalize /oobe /shutdown /mode:vm"
		}
	}
}
elseif ($mode -eq "RenameComputer") {
	# Used for the snapshot workaround
	LogWriter("Renaming computer to: " + $readComputerNewname)
	Rename-Computer -NewName $ComputerNewname -Force -ErrorAction SilentlyContinue
}
elseif ($mode -eq "JoinDomain") {
	# Stopping windows update service during the rollout process
	LogWriter("Stopping windows update service and MECM (if exist) during the rollout process")
	Stop-Service wuauserv -Force -NoWait -ErrorAction SilentlyContinue
	Stop-Service ccmexec -Force -NoWait -ErrorAction SilentlyContinue

	LogWriter("Check for PreJoin scripts")
	ExecuteFileAndAwait "$env:windir\Temp\PreJoin.exe"
	ExecuteFileAndAwait "$env:windir\Temp\PreJoin.cmd"
	ExecuteFileAndAwait "$env:windir\Temp\PreJoin.bat"
	ExecuteFileAndAwait "$env:windir\Temp\PreJoin.ps1"

	# Removing existing agent if exist
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	# Prevent removing language packs
	LogWriter("Prevent removing language packs")
	AddRegistyKey "HKLM:\Software\Policies\Microsoft\Control Panel\International"
	New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Control Panel\International" -Name "BlockCleanupOfUnusedPreinstalledLangPacks" -Value 1 -force

	# Removing Intune dependency
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement" -Recurse -Force -ErrorAction Ignore

	# Storing AadOnly to registry
	LogWriter("Storing AadOnly to registry: " + $AadOnly)
	AddRegistyKey "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime"
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "AadOnly" -Value $AadOnly -force

	# Flagging WaitForHybridJoin
	LogWriter("Storing WaitForHybridJoin to registry: " + $WaitForHybridJoin)
	New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "WaitForHybridJoin" -Value $WaitForHybridJoin -force

	# Checking for a saved time zone information
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime") {
		$timeZone = (Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -ErrorAction Ignore)."TimeZone.Origin"
		if ($timeZone -ne "" -and $timeZone -ne $null) {
			LogWriter("Setting time zone to: " + $timeZone)
			Set-TimeZone -Id $timeZone
		}
	}
	
	# Check for defender onboarding script
	if (Test-Path -Path "$env:windir\Temp\Onboard-NonPersistentMachine.ps1") {
		LogWriter("Onboarding to Defender for Endpoints (non-persistent)")
		ExecuteFileAndAwait "$env:windir\Temp\Onboard-NonPersistentMachine.ps1"
	} elseif (Test-Path -Path "$env:windir\Temp\WindowsDefenderATPOnboardingScript.cmd") {
		LogWriter("Onboarding to Defender for Endpoints (persistent)")
		ExecuteFileAndAwait "$env:windir\Temp\WindowsDefenderATPOnboardingScript.cmd"
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
		$retry = 3
		$ok = $false
		do {
			try {
				if ($DomainJoinOU -eq "") {
					Add-Computer -DomainName $DomainFqdn -Credential $psc -Force -ErrorAction Stop
					$ok = $true
					LogWriter("Domain joined successfully")
				} 
				else {
					Add-Computer -DomainName $DomainFqdn -OUPath $DomainJoinOU -Credential $psc -Force -ErrorAction Stop
					$ok = $true
					LogWriter("Domain joined successfully")
				}
			}
			catch {
				if ($retry -eq 0) { throw $_ }
				$retry--
				LogWriter("Retry domain join because of an error: $_")
				Start-Sleep -Seconds 10
			}
		} while ($ok -ne $true)
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
	}
 else {
		LogWriter("AAD only is selected. Skipping joining to a native AD, joining AAD")
		$aadJoinSuccessful = $false
		# check if already joined		
		$aadLoginLogfile = @(Get-ChildItem "C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\?.?.?.?\AADLoginForWindowsExtension*.*" -ErrorAction Ignore)[@(Get-ChildItem -Directory  "C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows\?.?.?.?\AADLoginForWindowsExtension*.*" -ErrorAction Ignore).count - 1].fullname
		if ($aadLoginLogfile -ne $null) {
			LogWriter("AAD-Logfile of aad join exist in folder: $aadLoginLogfile")
			$aadJoinMessage = (Select-String  -Path "$aadLoginLogfile" -pattern "BadRequest")
			if ($aadJoinMessage -ne $null) {
				$aadJoinMessage = "{" + $aadJoinMessage.ToString().split("{")[1..99]
				# AAD join failed
				LogWriter("AAD join failed with message: $($aadJoinMessage)")
				throw "AAD join failed with message: `n$($aadJoinMessage)"
			}
			$aadJoinMessage = (Select-String  -Path "$aadLoginLogfile" -pattern "Successfully joined|Device is already secure joined")

			if ($aadJoinMessage -ne $null) {
				$aadJoinMessage = "{" + $aadJoinMessage.ToString().split("{")[1..99]
				# AAD join sucessful
				LogWriter("Hosts is successfully joined to AAD (reported by logfile)")
				$aadJoinSuccessful = $true
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
			$aadPath = @(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows")[@(Get-ChildItem -Directory  "C:\Packages\Plugins\Microsoft.Azure.ActiveDirectory.AADLoginForWindows").count - 1].fullname
			Start-Process -wait -LoadUserProfile -FilePath "$aadPath\AADLoginForWindowsHandler.exe" -WorkingDirectory "$aadPath" -ArgumentList 'enable' -RedirectStandardOutput "$($LogDir)\Avd.AadJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.AadJoin.Warning.txt"
		}
		if ($JoinMem -eq "1") {
			LogWriter("Joining Microsoft Endpoint Management is selected. Try to register to MEM")
			Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/AzureSecureVMJoin /debug /MdmId 0000000a-0000-0000-c000-000000000000" -RedirectStandardOutput "$($LogDir)\Avd.MemJoin.Out.txt" -RedirectStandardError "$($LogDir)\Avd.MemJoin.Warning.txt"
		}
	}
	# check for disk handling
	$modifyDrives = $false
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime") {
		if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime").ChangeDrives -eq 1) {
			$disks = Get-WmiObject -Class win32_volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq 3 }
			foreach ($disk in $disks) { if ($disk.Name -eq 'D:\' -and $disk.Label -eq 'Temporary Storage') { $modifyDrives = $true } }
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

						Set-WMIInstance -Class Win32_PageFileSetting -Arguments @{name = 'c:\pagefile.sys'; InitialSize = 0; MaximumSize = 0 }
						LogWriter("Set pagefile to c:\pagefile.sys")
					}
				}
			} else { $modifyDrives = $false }
		}
	}
	
	# resize C: partition to fill up the disk if ExpandPartition!="0""
	if ($ExpandPartition -ne "0" -and $modifyDrives -eq $false) {
		LogWriter("Check C: partition for resizing")
		try {
			$defragSvc = Get-Service -Name defragsvc -ErrorAction SilentlyContinue
			Set-Service -Name defragsvc -StartupType Manual -ErrorAction SilentlyContinue
			$supportedSize = (Get-PartitionSupportedSize -DriveLetter "c" -ErrorAction Stop)
			if ((Get-Partition -DriveLetter "c").Size -lt $supportedSize.SizeMax) {
				LogWriter("Resize C: partition to fill up the disk")
				Resize-Partition -DriveLetter "c" -Size $supportedSize.SizeMax
			}
			Set-Service -Name defragsvc -StartupType $defragSvc.StartType -ErrorAction SilentlyContinue
		}
		catch {
			LogWriter("Resize C: partition failed: $_")
		}
	}

	# check to move pagefile finally to C
	if ($MovePagefileToC -eq "1") {
		LogWriter("Redirecting pagefile to C:")
		RedirectPageFileTo("c")
	} elseif (-not $modifyDrives) {
		RedirectPageFileToLocalStorageIfExist
	}
	ShowPageFiles
	
	# install Hydra Agent (Hydra only)
	if ($HydraAgentUri -ne "") {
		$uri = $HydraAgentUri
		$secret = $HydraAgentSecret
		$DownloadAdress = "https://$($uri)/Download/HydraAgent"
        $retry=3
        do {
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
                $retry=0
		    }
		    catch {
			    LogWriter("An error occurred while installing Hydra Agent: $_")
                $retry--
		    }
        } while ($retry -gt 0)
	}

	# install AVD Agent if a registration key given
	if ($WvdRegistrationKey -ne "") {
		# Detect Windows Server
		try {
			if ((Get-WmiObject -class Win32_OperatingSystem).Caption.Contains("Windows Server")) {
				LogWriter("Windows Server detected - Installing RDS-role")
				Add-WindowsFeature rds-rd-server
			}
		} catch {
			LogWriter("Error detecting Windows Server OS: $_")
		}
		if ([System.Environment]::OSVersion.Version.Major -gt 6) {
			LogWriter("Installing AVD agent")
			$retryCount = 0
			do {

				$ret = Start-Process -wait -PassThru -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgent.msi" -ArgumentList "/quiet /qn /norestart /passive RegistrationToken=${WvdRegistrationKey}"

				if ($ret.ExitCode -ne 0) {
					LogWriter("Installation ($retryCount) failed with exit code $($ret.ExitCode)")
					Start-Sleep -Seconds 15
				} else {
					LogWriter("Installation finished without an error")
				}
				$retryCount++
			} while ($ret.ExitCode -ne 0 -and $retryCount -le 20)

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
			}
			else {
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
				$triggerM.Subscription = '<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name=''WVD-Agent'']] and System[(Level=2) and (EventID=3277)]]</Select></Query></QueryList>' # and EventID=3019: '<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name=''WVD-Agent'']] and System[(Level=2) and ((EventID=3277) or (EventID=3277))]]</Select></Query></QueryList>'
				$actionM = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"RestartBootloader`""
				$settingsM = New-ScheduledTaskSettingsSet
				$taskM = New-ScheduledTask -Action $actionM -Principal $principal -Trigger $triggerM -Settings $settingsM -Description "Restarts the bootloader in case of an known issue (timeout, download error) while installing the RDagent"
				Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-1' -InputObject $taskM -ErrorAction Ignore
				Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentBootloader-Monitor-1' -ErrorAction Ignore
				LogWriter("Added new task to monitor the RDAgentBootloader")
			}
		}
		else {
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

	if ($parameters -and $parameters -ne "") {
		LogWriter("Running ApplyOsSettings")
		ApplyOsSettings
	}
	
	# Final reboot
	LogWriter("Finally restarting session host")
	Start-Process -FilePath PowerShell.exe -ArgumentList "-noexit -command & {Start-Sleep -Seconds 20; Restart-Computer -Force -ErrorAction SilentlyContinue}"
	#Restart-Computer -Force -ErrorAction SilentlyContinue
}
elseif ($Mode -eq "RunSysprep") {
	RunSysprepInternal $parameters
}
elseif ($Mode -eq "DataPartition") {
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
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter = 'z:' }
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
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter = 'D:' }
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
					Set-WmiInstance -input $drive -Arguments @{ DriveLetter = 'E:' }
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

				RedirectPageFileToLocalStorageIfExist
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
}
elseif ($Mode -eq "RDAgentBootloader") {
	$WaitForHybridJoin = (Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -ErrorAction Ignore)."WaitForHybridJoin"

	if ($WaitForHybridJoin -and $WaitForHybridJoin -eq "1") {
		LogWriter("Delaying the installation of the AVD boot loader. Waiting for the Hybrid-Join to Entra ID")
		
		$retryCount = 0
		while ($null -eq (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*" -ErrorAction SilentlyContinue) -and $retryCount -le 420) {
			$retryCount++
			Start-Sleep -Seconds 5
			LogWriter("Delaying the installation of the AVD boot loader. Waiting for the Hybrid-Join to Entra ID")
		}
		LogWriter("Delaying the installation of the AVD boot loader. Host is hybrid-joined: $($null -ne (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*" -ErrorAction SilentlyContinue))")
	}

	LogWriter("Installing AVD boot loader - current path is ${LocalConfig}")
	$ret = Start-Process -wait -PassThru -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgentBootLoader.msi" -ArgumentList "/quiet /qn /norestart /passive"
	LogWriter("Installing AVD boot loader completed with exit code: $($ret.ExitCode)")
	
	$retryCount = 0
	while ($ret.ExitCode -ne 0 -and $retryCount -le 120)
	{
		$retryCount++
		LogWriter("Exit code in not 0. Retrying one time the installion after 15 seconds. Retry count: $($retryCount)") 
		Start-Sleep -Seconds 15
		$ret = Start-Process -wait -PassThru -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgentBootLoader.msi" -ArgumentList "/quiet /qn /norestart /passive"
		LogWriter("Installing AVD boot loader completed with exit code: $($ret.ExitCode)")
	}
	

	LogWriter("Waiting for the service RDAgentBootLoader")
	$bootloaderServiceName = "RDAgentBootLoader"
	
	if (-not (WaitForServiceExist $bootloaderServiceName 30 6)) {
		throw "Retry limit exceeded: RDAgentBootLoader didn't become available"
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
	$triggerM.Subscription = '<QueryList><Query Id="0" Path="RemoteDesktopServices"><Select Path="RemoteDesktopServices">*[System[Provider[@Name=''Microsoft.RDInfra.RDAgent.Service.MonitoringAgentCheck'']] and System[(Level=3) and (Task=0) and (EventID=0)]]</Select></Query></QueryList>'
	$actionM = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$LocalConfig\ITPC-WVD-Image-Processing.ps1`" -Mode `"RepairMonitoringAgent`""
	$settingsM = New-ScheduledTaskSettingsSet
	$taskM = New-ScheduledTask -Action $actionM -Principal $principal -Trigger $triggerM -Settings $settingsM -Description "Repairs the Azure Monitoring Agent in case of an issue"
	Register-ScheduledTask -TaskName 'ITPC-AVD-RDAgentMonitoring-Monitor' -InputObject $taskM #-ErrorAction Ignore
	Enable-ScheduledTask -TaskName 'ITPC-AVD-RDAgentMonitoring-Monitor' -ErrorAction Ignore
	LogWriter "Monitoring the agent state on the first start to handle the SXS-Stack issue or other health check issues"
	$run = $true
	$counter = 0
	do {
		$avdAgentStateJson = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\HealthCheckReport" -ErrorAction Ignore)."AgentHealthCheckReport"
		if ($avdAgentStateJson -ne $null) {
			LogWriter "Got an AVD agent state"
			if ($avdAgentStateJson -like "*SxsStack listener is not ready*") {
				LogWriter "SxsStack listener is not ready / restarting bootloader" 
				Stop-Service -Name "RDAgentBootLoader"
				Start-Service -Name "RDAgentBootLoader"
				Start-Sleep -Seconds 60
				$counter = $counter + 10
			}
		}


		$allowedHealthChecks=@("MonitoringAgentCheck","UrlsAccessibleCheck")
		try {
			# $avdAgentStateJson = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\HealthCheckReport" -ErrorAction Ignore)."AgentHealthCheckReport"
			$oldIssueExist=$false
			if ($avdAgentStateJson -ne $null) {
				$avdAgentState = $avdAgentStateJson | ConvertFrom-Json
        
				$avdAgentState | Get-Member -MemberType NoteProperty | ForEach-Object {
					if ($_.Name -in $allowedHealthChecks) {
						$item=$avdAgentState.$($_.Name)
						if ($item.HealthCheckResult -eq 2) {
							$errorTime=[datetime]::Parse($item.AdditionalFailureDetails.LastHealthCheckInUTC)
							$errorLastMinutes=((Get-Date) -$errorTime).TotalMinutes
                
							if ($errorLastMinutes -gt 5) {
								LogWriter("Found a long lasting issue for $($_.Name): Issue is $errorLastMinutes minutes old")
								$oldIssueExist=$true
							}
						}
					}
				}
				if ($oldIssueExist) {
					LogWriter("Removing old error state from registry")
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\HealthCheckReport" -Name "AgentHealthCheckReport" -ErrorAction Ignore
				}
			}
		} catch {
			LogWriter("Cannot evaluate old error health states in registry: $_")
		}

		$counter++
		if ($counter -gt 60) { $run = $false }
		Start-Sleep -Seconds 10
	} while ($run)
}
elseif ($Mode -eq "ApplyOsSettings") {
	ApplyOsSettings
}
elseif ($Mode -eq "CleanFirstStart") {
	LogWriter("Cleaning up Azure Agent logs - current path is ${LocalConfig}")
	Remove-Item -Path "C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\*" -Include *.status  -Recurse -Force -ErrorAction SilentlyContinue
		
	# Restore deactivated services from the imaging process
	LogWriter("Reconfiguring disabled services")
	try {
		(Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime").PSObject.Properties | Where-Object { $_.Name -like "Service.*" } | ForEach-Object {
			$serviceName = $_.Name.split(".")[1]
			LogWriter("Setting serice $($serviceName) to $([System.ServiceProcess.ServiceStartMode]($_.Value))")
			Set-Service -Name $serviceName -StartupType ([System.ServiceProcess.ServiceStartMode]($_.Value)) -ErrorAction SilentlyContinue
		}
	} catch {
		LogWriter("Reconfiguring services failed: $_")
	}

	LogWriter("Disable scheduled task")
	try {
		# disable startup scheduled task
		Disable-ScheduledTask -TaskName 'ITPC-AVD-CleanFirstStart-Helper'
	}
	catch {
		LogWriter("Disabling scheduled task failed: " + $_.Exception.Message)
	}
}
elseif ($mode -eq "RestartBootloader") {
	$lastTimestamp = Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "RestartBootloaderLastRun" -ErrorAction SilentlyContinue
	$timeDiffSec = ([int][double]::Parse((Get-Date -UFormat %s))) - $lastTimestamp.RestartBootloaderLastRun

	if ($LastTimestamp -eq $null -or $timeDiffSec -gt 120) {
		$LogFile = $LogDir + "\AVD.AgentBootloaderErrorHandling.log"
		LogWriter "Stopping service"
		Stop-Service -Name "RDAgentBootLoader"
		LogWriter "Starting service"
		Start-Service -Name "RDAgentBootLoader"
		New-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -Name "RestartBootloaderLastRun" -Value ([int][double]::Parse((Get-Date -UFormat %s))) -force  -ErrorAction SilentlyContinue
	}
}
elseif ($mode -eq "RepairMonitoringAgent") {
	$LogFile = $LogDir + "\AVD.MonitorReinstall.log"
	$files = @(Get-ChildItem -Path "$($env:ProgramFiles)\Microsoft RDInfra\Microsoft.RDInfra.Geneva.Installer*.msi")
	if ($files.Length -eq 0) {
		LogWriter "Couldn't find binaries"
	}
 else {
		$file = $files[$files.Length - 1]
		LogWriter "Installing Monitoring Agent $file"
		Start-Process -wait -FilePath "$file" -ArgumentList "/quiet /qn /norestart /passive /l*v `"$($env:windir)\system32\logfiles\AVD-MonitoringAgentMsi.log`""
	}
}
elseif ($mode -eq "StartBootloader") {
	$LogFile = $LogDir + "\AVD.AgentBootloaderErrorHandling.log"
	if (WaitForServiceExist "RDAgentBootLoader" 5 480) {
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
	} else {
		LogWriter "The service was not found. Skipping the StartBootloader task"
	}
}
elseif ($mode -eq "StartBootloaderIfNotRunning") {
	# Workaround for a hidden system file
	RemoveHiddenIfExist "$env:windir\system32\VMAgentDisabler.dll"
	# Monitor service
	$serviceName = "RDAgentBootLoader"
	if (WaitForServiceExist $serviceName 5 480) {
		$interval = 30
		$run = $true
		$counter = 0
	
		$aadOnly=$false
		$aadOnly=Get-ItemProperty -Path "HKLM:\\SOFTWARE\ITProCloud\WVD.Runtime" -Name "AadOnly" -ErrorAction SilentlyContinue
		if ($aadOnly -ne $null -and $aadOnly.AadOnly -eq 1) {
			$aadOnly=$true
			LogWriter "Detected an AadOnly environment. Monitoring the Aad-join process and restart the bootloader if an error is shown"
		}

		do {
			Start-Sleep -Seconds $interval
			$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
			if ($service -ne $null -and $service.Status -ne [System.ServiceProcess.ServiceControllerStatus](4)) {
				LogWriter "Starting service: $serviceName"
				Start-Service -Name $serviceName -ErrorAction SilentlyContinue
			}
			# Restart bootloader in case of AadOnly and not joined to domain (force the agent to be completed)
			if ($aadOnly) {
				try {
					$healthCheck=Get-ItemProperty -Path "HKLM:\\SOFTWARE\Microsoft\RDInfraAgent\HealthCheckReport" -Name "AgentHealthCheckReport" -ErrorAction SilentlyContinue
					if ($healthCheck -ne $null) {
						$healthObj=$healthCheck.AgentHealthCheckReport | ConvertFrom-Json -ErrorAction SilentlyContinue
						if ($healthObj -ne $null) {
								if ($healthObj.DomainJoinedCheck.HealthCheckResult -ne 1) {
									LogWriter "DomainJoinFailure detected. Restarting RDAgentBootLoader"
									Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
									Start-Service -Name $serviceName -ErrorAction SilentlyContinue
									Start-Sleep -Seconds $interval
								}
						}
					}
				} catch {
					LogWriter "Getting the AVD health-state failed: $_"
				}
			}
			$counter++
			if ($counter -gt 10) { $interval = 90 }
			if ($counter -gt 20) { $run = $false }
		} while ($run)
	} else {
		LogWriter "The service was not found. Skipping the StartBootloaderIfNotRunning task"
	}
}
elseif ($mode -eq "JoinMEMFromHybrid") {
	# Check, if registry key exist
	if ($null -ne (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*" -ErrorAction SilentlyContinue)) {
		LogWriter("Device is AAD joined")
		if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\EnterpriseDesktopAppManagement") {
			LogWriter("Device is Intune managed")
			LogWriter("Removing schedule task")
			Unregister-ScheduledTask -TaskName "ITPC-AVD-Enroll-To-Intune" -Confirm:$false
		}
		else {
			LogWriter("Device is not Intune managed - starting registration")
			Start-Process -FilePath "$($env:windir)\System32\deviceenroller.exe" -ArgumentList "/c /AutoEnrollMDMUsingAADDeviceCredential" -Wait -NoNewWindow
		}
	}
 else {
		LogWriter("Device is not AAD joined")
		if (Test-Path -Path "$($env:WinDir)\system32\Dsregcmd.exe") {
			LogWriter("Triggering AAD join")
			Start-Process -wait -FilePath  "$($env:WinDir)\system32\Dsregcmd.exe" -ArgumentList "/join" -ErrorAction SilentlyContinue
		}
	}
}
