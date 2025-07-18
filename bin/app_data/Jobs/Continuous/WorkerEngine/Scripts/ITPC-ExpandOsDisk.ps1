﻿param(
    [string]$paramLogFileName="AVD.Hydra.log"
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
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
}
function OutputWriter($message)
{
    # Writes to logfile and is streamed to the output
    $global:Hydra_Output+="`r`n"+$message
    LogWriter($message)
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

LogWriter("Check C: partition for resizing")
RemoveReadOnlyFromScripts "$($MyInvocation.MyCommand.Path)"

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
