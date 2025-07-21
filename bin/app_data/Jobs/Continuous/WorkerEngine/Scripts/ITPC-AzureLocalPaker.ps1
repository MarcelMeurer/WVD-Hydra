Add-Type -AssemblyName System.IO.Compression.FileSystem

function LogWriter($message) {
	$message = "$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
}
function UnzipFile
{
    param([string]$zipfile, [string]$out)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $out)
}
function CleanPsLog() {
	#NO AddRegistyKey
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
function RemoveCryptoKey($path) {
	LogWriter("Remove ZIP")
    try {
        (gc $path) | ForEach-Object {
            if ($_ -like '*$CompressedIncludeScript=*') {
                '#' * $_.Length
            } else {
                $_
            }
        } | sc $path -Encoding UTF8
		if (!($path -like 'C:\Users\*')) {
			$aclNew=New-Object Security.AccessControl.DirectorySecurity
			$aclNew.SetSecurityDescriptorSddlForm("G:SY D:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)")
			$aclNew.SetAccessRuleProtection($true, $false)
			Set-Acl -Path $path -AclObject $aclNew -ErrorAction Stop # Set-Acl -Path ([System.IO.DirectoryInfo]::new($path).Parent.Parent.FullName) -AclObject $aclNew -ErrorAction Stop
		}
    } catch {
		LogWriter("Remove CryptoKey cause an exception: $_")
	}
}


# Define logfile
$LogDir = "$env:windir\system32\LogFiles"
$LogFile = $LogDir + "\AVD.Hydra-HCI-ScriptEngine.log"
CleanPsLog

###CompressedIncludeScript###
RemoveCryptoKey "$($MyInvocation.MyCommand.Path)"

$guid=(New-Guid).Guid
Remove-Item -Path "$($env:temp)\Hydra-ScriptInclude.$($guid).zip" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$($env:temp)\Hydra-ScriptInclude.$($guid).ps1" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue

Set-Content -Path "$($env:temp)\Hydra-ScriptInclude.$($guid).zip" -Value ([System.Convert]::FromBase64String($CompressedIncludeScript)) -Encoding Byte
UnzipFile "$($env:temp)\Hydra-ScriptInclude.$($guid).zip" "$($env:temp)\Hydra-ScriptInclude.$($guid).ps1" 

$CallScript="$($env:temp)\Hydra-ScriptInclude.$($guid).ps1\Hydra-ScriptInclude.ps1"
try {. "$($env:temp)\Hydra-ScriptInclude.$($guid).ps1\Hydra-ScriptInclude.ps1" @Args} catch {
    LogWriter "Error in running script: $_"
    throw $_
} finally {
    Remove-Item -Path "$($env:temp)\Hydra-ScriptInclude.$($guid).zip" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$($env:temp)\Hydra-ScriptInclude.$($guid).ps1" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
}