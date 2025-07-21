# This powershell script is part of Hydra
# Current Version of this script: 5.3

param(
    [string] $WvdRegistrationKey = '',
    [string] $DownloadNewestAgent = '1',					#Download the newes agent, event if a local agent exist
	[string] $AltAvdAgentDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcm1Ydg==',
	[string] $AltAvdBootloaderDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcnhySA=='
)

# Define logfile and dir
$LogDir="$env:windir\system32\logfiles"
$LogFile="$LogDir\AVD.AgentReinstall.log"

function LogWriter($message)
{
    # Writes to logfile
    $global:Hydra_Log+="`r`n"+$message
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
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
function AddRegistyKey($key) {
	if (-not (Test-Path $key)) {
		New-Item -Path $key -Force -ErrorAction SilentlyContinue
	}
}
function Decrypt-String ($encryptedString, $passPhrase) {
    try {
        $data = [Convert]::FromBase64String($encryptedString)
        $key  = [Convert]::FromBase64String($passPhrase)
        $iv   = $data[0..15]
        $ct   = $data[16..($data.Length - 1)]
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = 'CBC'; $aes.Key = $key; $aes.IV = $iv
        $cs = New-Object System.Security.Cryptography.CryptoStream (([IO.MemoryStream]::new($ct)),$aes.CreateDecryptor(),'Read')
        return ([IO.StreamReader]::new($cs)).ReadToEnd()
    } catch {
        return $encryptedString
    }
}
function RemoveCryptoKey($path) {
	LogWriter("Remove CryptoKey")
    try {
        (gc $path) | ForEach-Object {
            if ($_ -like '*####CryptoKeySet####*' -and $_ -like '*$CryptoKey=*' -and ($_ -notlike '*-and*')) {
                '#' * $_.Length
            } else {
                $_
            }
        } | sc $path -Encoding UTF8
		$name = Split-Path $path -Leaf
		$dir  = Split-Path $path -Parent
		if ($path -like 'C:\Packages\Plugins\*\Downloads\*' -and $name -like 'script*.ps1') {
			RemoveReadOnlyFromScripts $path
			$settingsPath="$(([System.IO.DirectoryInfo]::new($path).Parent.Parent.FullName))\RuntimeSettings\$(($name -split '\.')[0] -replace '[^\d]', '').settings"
			if (Test-Path -Path $settingsPath) {try {""|sc $settingsPath -Encoding UTF8 -ErrorAction stop} catch{}}
		}
		if ($path -like 'C:\Packages\Plugins\*\Downloads\*') {
			$aclNew=New-Object Security.AccessControl.DirectorySecurity
			$aclNew.SetSecurityDescriptorSddlForm("O:SY G:SY D:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)")
			$aclNew.SetAccessRuleProtection($true, $false)
			Set-Acl -Path ([System.IO.DirectoryInfo]::new($path).Parent.Parent.FullName) -AclObject $aclNew -ErrorAction Stop
		}
    } catch {
		LogWriter("Remove CryptoKey cause an exception: $_")
	}
}
function RemoveReadOnlyFromScripts($path){
    try {
		if ($path -like 'C:\Packages\Plugins\*\Downloads\*') {
			$dir  = Split-Path $path -Parent
			Get-ChildItem $dir -Filter 'script*.ps1' -File | ForEach-Object {
				if ($_.Attributes -band 'ReadOnly') { $_.Attributes = $_.Attributes -bxor 'ReadOnly' }
			}
		}
    } catch {
        LogWriter("Remove ReadOnly from scripts caused an issue: $_")
    }
}
function CleanPsLog() {
	AddRegistyKey "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
	New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 0 -force -ErrorAction SilentlyContinue
    try {Disable-PSTrace} catch {}
	try {
		try {$l1 = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration "Windows PowerShell"} catch {$l1=$null}
		try {$l2 = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration "Microsoft-Windows-PowerShell/Operational"} catch {$l2=$null}
		Clear-EventLog -LogName "Windows PowerShell" -ErrorAction SilentlyContinue
		Start-Process -FilePath "$env:windir\system32\wevtutil.exe" -ArgumentList 'cl "Microsoft-Windows-PowerShell/Operational"' -Wait -ErrorAction SilentlyContinue
		try {$l2.IsEnabled=$false;$l2.SaveChanges()} catch {throw $_}
		#Change permission
		Start-Process -FilePath "$env:windir\system32\wevtutil.exe" -ArgumentList 'sl "Windows PowerShell" /ca:"O:SYG:SYD:(A;;0x1;;;SY)"' -Wait -ErrorAction SilentlyContinue
		Start-Process -FilePath "$env:windir\system32\wevtutil.exe" -ArgumentList 'sl "Microsoft-Windows-PowerShell/Operational" /ca:"O:SYG:SYD:(A;;0x1;;;SY)"' -Wait -ErrorAction SilentlyContinue
		$cleanIt=$false
		try {
		if ($l1.SecurityDescriptor -ne "O:SYG:SYD:(A;;0x1;;;SY)" -or $l2.SecurityDescriptor -ne "O:SYG:SYD:(A;;0x1;;;SY)" -or $l2.IsEnabled -or (Test-Path -Path "$($l2.LogFilePath.Replace("%SystemRoot%",$env:windir))") -or (Get-WinEvent -LogName $l1.LogName -MaxEvents 1 -ErrorAction SilentlyContinue) -or (Get-WinEvent -LogName $l2.LogName -MaxEvents 1 -ErrorAction SilentlyContinue)) {
			$cleanIt=$true
			LogWriter("CleanPsLog check is true")
		}
		} catch {
			$cleanIt=$true
			LogWriter("CleanPsLog caused an issue while checking the log configuration: $_")
		}
		if ($cleanIt){
			LogWriter("CleanPsLog clean-up files")
			Stop-Service -Name EventLog -Force -ErrorAction SilentlyContinue
			Remove-Item "$($l1.LogFilePath.Replace("%SystemRoot%",$env:windir))" -Force -ErrorAction SilentlyContinue
			Remove-Item "$($l2.LogFilePath.Replace("%SystemRoot%",$env:windir))" -Force -ErrorAction SilentlyContinue
			Start-Service -Name EventLog -ErrorAction SilentlyContinue
		}
	} catch {
			LogWriter("CleanPsLog caused an issue: $_")
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

# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"

if ($AltAvdAgentDownloadUrl64) { $AltAvdAgentDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdAgentDownloadUrl64)) }
if ($AltAvdBootloaderDownloadUrl64) { $AltAvdBootloaderDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdBootloaderDownloadUrl64)) }

# Main
LogWriter("Starting ITPC-WVD-ReinstallAvdAgent")
CleanPsLog

####CryptoKey####
if ($CryptoKey) {RemoveCryptoKey "$($MyInvocation.MyCommand.Path)"} else {RemoveReadOnlyFromScripts "$($MyInvocation.MyCommand.Path)"}

if ($CryptoKey) {
    LogWriter("Decrypting parameters")
	if ($WvdRegistrationKey) { $WvdRegistrationKey = Decrypt-String $WvdRegistrationKey $CryptoKey }
}

# Stopping schedule tasks
Stop-ScheduledTask -TaskName "ITPC-AVD-RDAgentMonitoring-Monitor" -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName "ITPC-AVD-RDAgentBootloader-Monitor-1" -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName "ITPC-AVD-RDAgentBootloader-Monitor-2" -ErrorAction SilentlyContinue

# check for the existend of the helper scripts
if ((Test-Path ($LocalConfig)) -eq $false) {
        # Create local directory
        LogWriter("Copy files to local session host or downloading files from Microsoft")
        new-item $LocalConfig -ItemType Directory -ErrorAction Ignore
        try { (Get-Item $LocalConfig -ErrorAction Ignore).attributes = "Hidden" } catch {}
    }

    if ((Test-Path ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
        if ((Test-Path ($ScriptRoot + "\Microsoft.RDInfra.RDAgent.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
            LogWriter("Downloading RDAgent")
            DownloadFile "https://go.microsoft.com/fwlink/?linkid=2310011" ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi") $AltAvdAgentDownloadUrl
        }
        else { Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($LocalConfig + "\") }
    }
    if ((Test-Path ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
        if ((Test-Path ($ScriptRoot + "\Microsoft.RDInfra.RDAgentBootLoader.msi ")) -eq $false -or $DownloadNewestAgent -eq "1") {
            LogWriter("Downloading RDBootloader")
            DownloadFile "https://go.microsoft.com/fwlink/?linkid=2311028" ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi") $AltAvdBootloaderDownloadUrl
        }
        else { Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgentBootLoader.msi" -Destination ($LocalConfig + "\") }
    }


LogWriter("Removing existing Remote Desktop Agent Boot Loader")
Uninstall-Package -Name "Remote Desktop Agent Boot Loader" -AllVersions -Force -ErrorAction SilentlyContinue 
LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
Uninstall-Package -Name "Remote Desktop Services Infrastructure Agent" -AllVersions -Force -ErrorAction SilentlyContinue 
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore



if ([System.Environment]::OSVersion.Version.Major -gt 6) {
    LogWriter("Installing AVD agent")
    Start-Process -wait -FilePath "${LocalConfig}\Microsoft.RDInfra.RDAgent.msi" -ArgumentList "/quiet /qn /norestart /passive RegistrationToken=${WvdRegistrationKey}"
    if ($true) {
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

CleanPsLog