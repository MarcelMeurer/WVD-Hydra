# This powershell script is part of WVD Admin - see https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/ for more information
# Current Version of this script: 2.6

param(

	[string] $Secret='',

	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('Generalize','JoinDomain')]
	[string] $Mode,
	[string] $LocalAdminName='localAdmin',
	[string] $LocalAdminPassword='',
	[string] $DomainJoinUserName='',
	[string] $DomainJoinUserPassword='',
	[string] $DomainJoinOU='',
	[string] $DomainFqdn='',
	[string] $WvdRegistrationKey='',
	[string] $LogDir="$env:windir\system32\logfiles"
)

function LogWriter($message)
{
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}

# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"

# Define logfile
$LogFile=$LogDir+"\WVD.Customizing.log"

# Main
LogWriter("Starting ITPC-WVD-Image-Processing in mode ${Mode}")


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

if ($mode -eq "Generalize") {
	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Agent Boot Loader"}
	if ($app -ne $null) {$app.uninstall()}
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Services Infrastructure Agent"}
	if ($app -ne $null) {$app.uninstall()}
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
	# Checking for a saved time zone information
	if (Test-Path -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime") {
		$timeZone=(Get-ItemProperty -Path "HKLM:\SOFTWARE\ITProCloud\WVD.Runtime" -ErrorAction Ignore)."TimeZone.Origin"
		if ($timeZone -ne "" -and $timeZone -ne $null) {
			LogWriter("Setting time zone to: "+$timeZone)
			Set-TimeZone -Id $timeZone
		}
	}
		
	LogWriter("Joining domain")
	$psc = New-Object System.Management.Automation.PSCredential($DomainJoinUserName, (ConvertTo-SecureString $DomainJoinUserPassword -AsPlainText -Force))

	if ($DomainJoinOU -eq "")
	{
		Add-Computer -DomainName $DomainFqdn -Credential $psc -Force -ErrorAction Stop
	} 
	else
	{
		Add-Computer -DomainName $DomainFqdn -OUPath $DomainJoinOU -Credential $psc -Force -ErrorAction Stop
	}
	LogWriter("Joining domain successed: "+$hasJoined)

	if ([System.Environment]::OSVersion.Version.Major -gt 6) {
		LogWriter("Installing WVD boot loader - current path is ${LocalConfig}")
		Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgentBootLoader.msi" -ArgumentList "/q"
		LogWriter("Installing WVD agent")
		Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgent.msi" -ArgumentList "/q RegistrationToken=${WvdRegistrationKey}"
	} else {
        if ((Test-Path "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi") -eq $false) {
            LogWriter("Downloading Microsoft.RDInfra.WVDAgent.msi")
            Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3JZCm' -OutFile "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi"
        }
        if ((Test-Path "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi") -eq $false) {
            LogWriter("Downloading Microsoft.RDInfra.WVDAgentManager.msi")
            Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RE3K2e3' -OutFile "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi"
        }
		LogWriter("Installing WVDAgent")
        Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.WVDAgent.msi" -ArgumentList "/q RegistrationToken=${WvdRegistrationKey}"
        LogWriter("Installing WVDAgentManager")
		Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.WVDAgentManager.msi" -ArgumentList '/q'
	}


	LogWriter("Enabling ITPC-LogAnalyticAgent and MySmartScale if exist") 
	Enable-ScheduledTask  -TaskName "ITPC-LogAnalyticAgent for RDS and Citrix" -ErrorAction Ignore
	Enable-ScheduledTask  -TaskName "ITPC-MySmartScaleAgent" -ErrorAction Ignore

	LogWriter("Finally restarting session host")

	# final reboot
	Restart-Computer -Force
}