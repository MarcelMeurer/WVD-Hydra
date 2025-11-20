# This powershell script is part of Hydra
# Current Version of this script: 5.3
param(
    [string]$paramLogFileName="AVD.Hydra.log",
    [string]$installHydraAgent="1",
    [string]$uri,
    [string]$secret,
    [string]$sceneSecret,
    [string]$renameFrom64,
    [string]$renameTo64
);

 Add-Type -AssemblyName System.IO.Compression.FileSystem

# Define logfile and dir
$LogDir="$env:windir\system32\logfiles"
$LogFile="$LogDir\$paramLogFileName"
$ErrorActionPreference="stop"

$global:Hydra_Log=""
$global:Hydra_Output=""
function LogWriter($message)
{
    # Writes to logfile
    $global:Hydra_Log+="`r`n"+$message
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
}
function OutputWriter($message)
{
    # Writes to logfile and is streamed to the output
    $global:Hydra_Output+="`r`n"+$message
    LogWriter($message)
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
function UnzipFile ($zipfile, $outdir)
{
    # Based on https://gist.github.com/nachivpn/3e53dd36120877d70aee
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
function DownloadFile ( $url, $outFile)
{
    $i=6
    $ok=$false;
    do {
        try {
            LogWriter("Try to download file")
            (New-Object System.Net.WebClient).DownloadFile($url, $outFile)
            [System.IO.Compression.ZipFile]::OpenRead($outFile).Dispose()
            $ok=$true
        } catch {
            $i--;
            if ($i -le 0) {
                throw 
            }
            LogWriter("Re-trying download after 10 seconds")
            Start-Sleep -Seconds 10
		}
    } while (!$ok)
}
function StopAndRemoveSchedTask($taskName) {
	$task = Get-ScheduledTask -TaskName  $taskName -ErrorAction SilentlyContinue
	if ($task -ne $null) {
		LogWriter("Stopping and removing task $taskName")
		Stop-ScheduledTask -TaskName $taskName -ErrorAction Ignore
		Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
	}
}

####CryptoKey####
if ($CryptoKey) {RemoveCryptoKey "$($MyInvocation.MyCommand.Path)"} else {RemoveReadOnlyFromScripts "$($MyInvocation.MyCommand.Path)"}

if ($CryptoKey) {
    LogWriter("Decrypting parameters")
	if ($secret) { $secret = Decrypt-String $secret $CryptoKey }
    if ($sceneSecret) { $sceneSecret = Decrypt-String $sceneSecret $CryptoKey }
}

$DownloadAdress="https://$($uri)/Download/HydraAgent"
if ($renameFrom64) { $renameFrom = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($renameFrom64)) }
if ($renameTo64) { $renameTo = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($renameTo64)) }

CleanPsLog

$global:Hydra_Output="Done"

# CLean-up
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

Remove-Item "C:\Packages\Plugins\Microsoft.Powershell.DSC" -Recurse -Force -ErrorAction SilentlyContinue


# Install Hydra Agent if selected
if ($installHydraAgent -eq "1") {
    try {
        LogWriter("Installing Hydra Agent")
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
        LogWriter("Configuring the Hydra Agent to run in CPC/Scene mode")
        cd "$env:ProgramFiles\ITProCloud.de\HydraAgent"
        . "$env:ProgramFiles\ITProCloud.de\HydraAgent\HydraAgent.exe" -i -u "wss://$($uri)/wsx" -s "$secret" -t "$sceneSecret"
        Start-Sleep -Seconds 3
        Start-ScheduledTask -TaskName 'ITPC-AVD-Hydra-Helper' -ErrorAction Ignore
    }
    catch {
        $global:Hydra_Output="An error occurred: $_"
        throw $_
    }
}

# Rename Computer if needed
try {
    # Validate both variables
    if (![string]::IsNullOrWhiteSpace($renameFrom) -and 
        ![string]::IsNullOrWhiteSpace($renameTo) -and 
        $renameFrom -ne $renameTo) {
        $currentName = $env:ComputerName
        # Check if current name contains the source string
        if ($currentName -like "*$renameFrom*") {
            # Build the new computer name
            $newName = $currentName -replace [regex]::Escape($renameFrom), $renameTo

            # Proceed only if the name actually changes
            if ($newName -ne $currentName) {
                LogWriter("Renaming computer from '$currentName' to '$newName'")

                try {
                    # Perform rename (no credentials, forced, may contact domain)
                    Rename-Computer -NewName $newName -Force
                    LogWriter("Rename command executed successfully.")
                }
                catch {
                    LogWriter("Error during Rename-Computer: $($_.Exception.Message)")
                    throw "Computer rename failed: $($_.Exception.Message)"
                }
            }
            else {
                LogWriter("New name is identical to current name. No action required.")
            }
        }
        else {
            LogWriter("Current name does not contain '$renameFrom'. No rename performed.")
        }
    }
    else {
        LogWriter("Invalid or identical rename parameters. Rename skipped.")
    }
}
catch {
    LogWriter "Unexpected error: $($_.Exception.Message)" "ERROR"
    throw
}

LogWriter($global:Hydra_Output)
OutputWriter("ScriptReturnMessage:{$($global:Hydra_Output)}:ScriptReturnMessage")
CleanPsLog
