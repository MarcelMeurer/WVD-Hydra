# This powershell script is part of WVDAdmin and Project Hydra
# Current Version of this script: 1.3

# The purpose is to overwrite an existing script on the Azure backend (to destroy the caching)

function LogWriter($message) {
	$message = "$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists("$env:windir\system32\logfiles")) { try { write-output($message) | Out-File "$env:windir\system32\logfiles\AVD.PostProcessing.log" -Append } catch {} }
}

LogWriter("Postprocessing script started.")
try {
	if (Test-Path -Path "$env:temp\RolloutCustomization-Finished.flag") {
		LogWriter("Removing $env:temp\RolloutCustomization-Finished.flag")
		Remove-Item "$env:temp\RolloutCustomization-Finished.flag" -Force -ErrorAction SilentlyContinue
	}
	$path = $MyInvocation.MyCommand.Definition
	$name = Split-Path $path -Leaf
	$dir  = Split-Path $path -Parent
	if ($path -like 'C:\Packages\Plugins\*\Downloads\*' -and $name -like 'script*.ps1') {
		Get-ChildItem $dir -Filter 'script*.ps1' -File | ForEach-Object {
			if ($_.Attributes -band 'ReadOnly') { $_.Attributes = $_.Attributes -bxor 'ReadOnly' }
		}
	}
} catch {
	LogWriter("Postprocessing caused an issue: $_")
}
LogWriter("Postprocessing script finished.")
