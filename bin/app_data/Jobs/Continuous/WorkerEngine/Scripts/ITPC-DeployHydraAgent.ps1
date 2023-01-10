param(
    [string]$paramLogFileName="AVD.Hydra.log",
    [string]$uri,
    [string]$secret
);

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
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}
function OutputWriter($message)
{
    # Writes to logfile and is streamed to the output
    $global:Hydra_Output+="`r`n"+$message
    LogWriter($message)
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
function DownloadFile ( $url, $outFile)
{
    $i=3
    $ok=$false;
    do {
        try {
            LogWriter("Try to download file")
            Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
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

$DownloadAdress="https://$($uri)/Download/HydraAgent"


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
Write-host("ScriptReturnMessage:{$($global:Hydra_Output)}:ScriptReturnMessage")