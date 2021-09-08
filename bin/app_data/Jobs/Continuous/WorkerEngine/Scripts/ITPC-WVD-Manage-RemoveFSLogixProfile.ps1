# {"Name": "Delete FSLogix user profile","Description":"Delete the FSLogix profile of the given user. The user must be logged off and the share accessible by the given service account"}
param(
    [string]$paramLogFileName="AVD.DeleteFSLogixProfile.log",
   	[string]$users="",
    [string]$serviceDomainUser="",
    [string]$serviceDomainPw=""
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
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}

LogWriter("Remove FSLogix profile script starts. Parameter: $($users)")

foreach ($user in $users.Split(";")) {
    if ($user -ne "") {
        try {
            $user=$user.Trim()
            LogWriter("Processing: $user")
            $search = [adsisearcher]"(&(ObjectCategory=Person)(ObjectClass=User)(|(userprincipalname=$user)(cn=$user)))"
            $adUser = $search.FindOne()
            if ($adUser) {
                $sid=(New-Object System.Security.Principal.SecurityIdentifier([byte[]]($adUser.Properties.objectsid |out-string -Stream),0)).Value
                LogWriter("User found in Active Directory: $($adUser.Path) with SID $sid")
                $profilePath=Get-ItemPropertyValue -Path HKLM:\SOFTWARE\FSLogix\Profiles -Name VHDLocations
                if ((Get-ItemPropertyValue -Path HKLM:\Software\Policies\FSLogix\ODFC -Name FlipFlopProfileDirectoryName -ErrorAction SilentlyContinue) -eq 1) {
                    $profilePathUser="$($adUser.Properties.samaccountname)_$($profilePath)\$($sid)"
                    LogWriter("FlipFlopProfileDirectoryName is set to 1")
                } else  {
                    $profilePathUser="$($profilePath)\$($sid)_$($adUser.Properties.samaccountname)"
                }
                LogWriter("Default FSLogix profile path is: $profilePathUser")
                if (!(Test-Path -Path "$profilePath" -ErrorAction SilentlyContinue)) {
                    LogWriter("Using service account to authenticate to the file share")
                    $psc = New-Object System.Management.Automation.PSCredential("$serviceDomainUser", (ConvertTo-SecureString "$serviceDomainPw" -AsPlainText -Force))
                    New-PSDrive -Name Profile -PSProvider FileSystem -Root "$profilePath" -Credential $psc
                }
                LogWriter("Start to remove all files in the path")
                Remove-Item -Path "$profilePathUser\*" -Force


            } else {
                LogWriter("WARNING: User $user couldn't be found in Active Directory")
            }

        } catch {
            LogWriter("ERROR: An exception occurs: $_.Message")
        }
    }
}

# use the next line to give a return message
Write-host("ScriptReturnMessage:{$($global:messages)}:ScriptReturnMessage")
