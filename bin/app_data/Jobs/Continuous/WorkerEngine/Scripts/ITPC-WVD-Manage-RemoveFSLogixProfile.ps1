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

# set serviceDomainCredentials
$serviceDomainUser=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainUser64))
$serviceDomainPw=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainPw64))

$global:messages=""
function LogWriter($message)
{
    $global:messages+="`r`n"+$message
    $message="$(Get-Date ([datetime]::UtcNow) -Format "o") $message"
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
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
    }
    return $newValue
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

                # Test for custom naming
                $dirName=(Get-Item -Path HKLM:\SOFTWARE\FSLogix\Profiles -ErrorAction SilentlyContinue).GetValue("SIDDirNameMatch")

                if ($dirName -eq $null -or $dirName -eq "") {
                    $regPath1="HKLM:\Software\FSLogix\Profiles"
                    $regPath2="HKLM:\Software\Policies\FSLogix\ODFC"
                    $flipFlop=$false
                                        
                    if ((Test-Path $regPath1) -and (Get-Item $regPath1 -ErrorAction SilentlyContinue).GetValue("FlipFlopProfileDirectoryName") -eq 1) {$flipFlop=$true}
                    if ((Test-Path $regPath2) -and (Get-Item $regPath2 -ErrorAction SilentlyContinue).GetValue("FlipFlopProfileDirectoryName") -eq 1) {$flipFlop=$true}
                    if ($flipFlop) {
                        $profilePathUser="$($profilePath)\$($adUser.Properties.samaccountname)_$($sid)"
                        LogWriter("FlipFlopProfileDirectoryName is set to 1")
                    } else  {
                        $profilePathUser="$($profilePath)\$($sid)_$($adUser.Properties.samaccountname)"
                    }
                } else {
                    $env:userName=$adUser.Properties.samaccountname
                    $dirName=ResolveEnvVariable($dirName)
                    $profilePathUser="$($profilePath)\$dirName"
                }

                LogWriter("Default FSLogix profile path is: $profilePathUser in $profilePath")
                if (!(Test-Path -Path "$profilePathUser" -ErrorAction SilentlyContinue)) {
                    LogWriter("Using service account to authenticate to the file share")
                    $psc = New-Object System.Management.Automation.PSCredential("$serviceDomainUser", (ConvertTo-SecureString "$serviceDomainPw" -AsPlainText -Force))
                    New-PSDrive -Name Profile -PSProvider FileSystem -Root "$profilePathUser" -Credential $psc
                }
                if (-not (Test-Path $profilePathUser)) {
                    throw "The path $profilePathUser doesn't exist"
                }
                LogWriter("Start to remove all files in the path")
                Get-ChildItem -Path "$profilePathUser\*" -Include *.vhd* | Where { ! $_.PSIsContainer } | Remove-Item -Force -Confirm:$false
                LogWriter("Done")


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
