# This powershell script is part of Hydra
# Current Version of this script: 5.3
param(
    [string]$paramLogFileName="AVD.Hydra.log",
    [string]$uri,
    [string]$secret
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

####CryptoKey####
if ($CryptoKey) {RemoveCryptoKey "$($MyInvocation.MyCommand.Path)"} else {RemoveReadOnlyFromScripts "$($MyInvocation.MyCommand.Path)"}

if ($CryptoKey) {
    LogWriter("Decrypting parameters")
	if ($secret) { $secret = Decrypt-String $secret $CryptoKey }
}

$DownloadAdress="https://$($uri)/Download/HydraAgent"
CleanPsLog

$global:Hydra_Output="Done"
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
    Start-Sleep -Seconds 3
    Start-ScheduledTask -TaskName 'ITPC-AVD-Hydra-Helper' -ErrorAction Ignore
}
catch {
    $global:Hydra_Output="An error occurred: $_"
    throw $_
}


LogWriter($global:Hydra_Output)
OutputWriter("ScriptReturnMessage:{$($global:Hydra_Output)}:ScriptReturnMessage")
CleanPsLog
