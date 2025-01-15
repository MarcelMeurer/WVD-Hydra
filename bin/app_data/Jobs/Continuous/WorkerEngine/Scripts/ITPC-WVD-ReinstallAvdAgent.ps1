# This powershell script is part of Hydra
# Current Version of this script: 4.9

param(
    [string] $WvdRegistrationKey = '',
    [string] $DownloadNewestAgent = '1'					#Download the newes agent, event if a local agent exist
)

function DownloadFile ( $url, $outFile) {
    $i = 3
    $ok = $false;
    do {
        try {
            LogWriter("Try to download file")
            Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
            $ok = $true
        }
        catch {
            $i--;
            if ($i -le 0) {
                throw 
            }
            LogWriter("Re-trying download after 10 seconds")
            Start-Sleep -Seconds 10
        }
    } while (!$ok)
}

# Define static variables
$LocalConfig="C:\ITPC-WVD-PostCustomizing"

# Main
LogWriter("Starting ITPC-WVD-ReinstallAvdAgent")

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
            DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" ($LocalConfig + "\Microsoft.RDInfra.RDAgent.msi")
        }
        else { Copy-Item "${PSScriptRoot}\Microsoft.RDInfra.RDAgent.msi" -Destination ($LocalConfig + "\") }
    }
    if ((Test-Path ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi")) -eq $false -or $DownloadNewestAgent -eq "1") {
        if ((Test-Path ($ScriptRoot + "\Microsoft.RDInfra.RDAgentBootLoader.msi ")) -eq $false -or $DownloadNewestAgent -eq "1") {
            LogWriter("Downloading RDBootloader")
            DownloadFile "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" ($LocalConfig + "\Microsoft.RDInfra.RDAgentBootLoader.msi")
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

