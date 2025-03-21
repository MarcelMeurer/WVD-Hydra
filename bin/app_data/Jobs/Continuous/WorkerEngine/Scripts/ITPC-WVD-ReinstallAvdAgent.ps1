# This powershell script is part of Hydra
# Current Version of this script: 5.0

param(
    [string] $WvdRegistrationKey = '',
    [string] $DownloadNewestAgent = '1',					#Download the newes agent, event if a local agent exist
	[string] $AltAvdAgentDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcm1Ydg==',
	[string] $AltAvdBootloaderDownloadUrl64 = 'aHR0cHM6Ly9xdWVyeS5wcm9kLmNtcy5ydC5taWNyb3NvZnQuY29tL2Ntcy9hcGkvYW0vYmluYXJ5L1JXcnhySA=='
)

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

# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"

if ($AltAvdAgentDownloadUrl64) { $AltAvdAgentDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdAgentDownloadUrl64)) }
if ($AltAvdBootloaderDownloadUrl64) { $AltAvdBootloaderDownloadUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AltAvdBootloaderDownloadUrl64)) }

# Main
LogWriter("Starting ITPC-WVD-ReinstallAvdAgent")

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

