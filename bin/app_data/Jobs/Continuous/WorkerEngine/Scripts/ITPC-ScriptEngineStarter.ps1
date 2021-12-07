param(
    [string]$paramLogFileName="AVD.Hydra.log",
    [string]$serviceDomainUser64="",
    [string]$serviceDomainPw64=""
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
function RunScript
{
	param(
		[string]$Id,
		[string]$Name64="",
		[string]$Parameters64="",
		[bool]$IgnoreErrors=$true,
		[string]$Script64
	)
    # Example: RunScript -Id "0000000" -Name "test script" -Parameters64 "fsfwefwe" -IgnoreErrors $true -Script64 "cGFyYW0oDQogICAgW3N0cmluZ10kdGVzdD0iIg0KKTsNCg0KDQp3cml0ZS1ob3N0ICJXaWUgZ2VodCBlcyBNci4gJHRlc3QiDQo="
    $hydraScriptLocation=Get-Location
    write-output([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($script64))) | Out-File "$($id).ps1"
    try {
       $Name=$([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Name64)))
       OutputWriter("HydraScriptEngine: START $Name")
       $global:Hydra_Script_Name=$Name
       $parameters=$([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Parameters64)))
       Invoke-Expression -Command ".\$($id).ps1 $parameters"
       OutputWriter("HydraScriptEngine: END")
       Set-Location $hydraScriptLocation
    } catch {
        Set-Location $hydraScriptLocation
        if (!$IgnoreErrors) {
            OutputWriter("HydraScriptEngine: FAILED-STOP Script failed: $_")
            throw $_
        } else {
            OutputWriter("HydraScriptEngine: FAILED-CONT Script failed but runtime will continue: $_")
        }
    }
}

if ($serviceDomainPw64) {
    LogWriter("Setting credentials for user $serviceDomainUser")

    $serviceDomainUser=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainUser64))
    $serviceDomainPw=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($serviceDomainPw64))

    $global:Hydra_ServiceAccount_PSC = New-Object System.Management.Automation.PSCredential($serviceDomainUser, (ConvertTo-SecureString $serviceDomainPw -AsPlainText -Force))
    $serviceDomainPw=""
    $serviceDomainPw64=""
}
#HYDRA:::INITIALIZEMASTERSCRIPT#

#HYDRA:::SCRIPTS#


# use the next line to give a return message
Write-host("ScriptReturnMessage:{$($global:Hydra_Output)}:ScriptReturnMessage")
