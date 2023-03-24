# This powershell script is part of Hydra
# Current Version of this script: 1.0

param(
	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('InstallApps','UpdateAllApps')]
	[string] $Mode,
    [string] $Apps64 = ''              # Only used in mode InstallApps
)

function DownloadFile ($url, $outFile) {
    $i = 3
    $ok = $false;
    do {
        try {
            LogWriter("Try to download file")
            Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
            $ok = $true
        }
        catch {
            $i--;
            if ($i -le 0) {
                throw 
            }
            LogWriter("Re-trying download after 10 seconds")
            Start-Sleep -Seconds 10
        }
    } while (!$ok)
}

LogWriter("Microsoft Package Manager Installer")



$folder=@(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" -ErrorAction Ignore)
if ($folder.count -eq 0 -or ($folder[0].VersionInfo.FileVersionRaw.Major -eq 1 -and $folder[0].VersionInfo.FileVersionRaw.Minor -le 19)) {
    LogWriter("Downloading Microsoft Package Manager / Winget")
    DownloadFile "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" "$($env:temp)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
	Add-AppxProvisionedPackage -Online -PackagePath "$($env:temp)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense 
}
$folder=@(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" -ErrorAction Ignore)
Copy-Item -Path "$($folder[0].PSParentPath)\*.*" -Destination "$env:temp\WinGet\" -Force



if ($mode -eq "InstallApps") {
    $apps=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Apps64));
    $appsObj=$apps|ConvertFrom-Json
    
    $appInstalled=""
    $appWasInstalled=""
    $appCouldntInstalled=""
    $appsObj | Sort-Object -Property Order | ForEach-Object {
        LogWriter("Installing $($_.Name)")
        $rval=Start-Process -PassThru -FilePath "$env:temp\WinGet\WinGet.exe" -Wait -ArgumentList "install `"$($_.Id)`" --verbose --disable-interactivity  --accept-source-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetInstaller.$($_.Id).Out.txt" -RedirectStandardError "$($LogDir)\WinGetInstaller.$($_.Id).Warning.txt"
        # one retry
        if (($rval.ExitCode -ne -1978335189) -and ($rval.ExitCode -ne 0)) {
            LogWriter("Installing $($_.Name) - again")
            $rval=Start-Process -PassThru -FilePath "$env:temp\WinGet\WinGet.exe" -Wait -ArgumentList "install `"$($_.Id)`" --verbose --disable-interactivity  --accept-source-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetInstaller.$($_.Id).Out.txt" -RedirectStandardError "$($LogDir)\WinGetInstaller.$($_.Id).Warning.txt"
        }
        if ($rval.ExitCode -eq -1978335189) {
            if ($appWasInstalled -eq "") {
                $appWasInstalled=$_.Name
            } else {
                $appWasInstalled+=", $($_.Name)"
            }
        } elseif ($rval.ExitCode -eq -1978335210) {
            LogWriter("$($_.Id) is ambiguous.")
            throw "$($_.Id) is ambiguous."
        } elseif ($rval.ExitCode -ne 0) {
            LogWriter("There was an issue installing the application $($_.Name). Return value is $($rval.ExitCode)")
            if ($appCouldntInstalled -eq "") {
                $appCouldntInstalled=$_.Name
            } else {
                $appCouldntInstalled+=", $($_.Name)"
            }
        } else {
            if ($appInstalled -eq "") {
                $appInstalled=$_.Name
            } else {
                $appInstalled+=", $($_.Name)"
            }
        }
    }
    $output=""
    if ($appInstalled -ne "") {
        $output="$appInstalled installed"
    }    
    if ($appWasInstalled -ne "") {
        if ($output -ne "") {$output+="; "}
        $output+="Some of the appliation where still installed: $appWasInstalled"
    }
    if ($appCouldntInstalled -ne "") {
        if ($output -ne "") {$output+="; "}
        $output+="Some of the appliation couldn't installed or updated: $appCouldntInstalled"
    }
    OutputWriter($output)
} else {
    LogWriter("Updating all apps on the local host")
    $rval=Start-Process -PassThru -FilePath "$env:temp\WinGet\WinGet.exe" -Wait -ArgumentList "upgrade --all --silent --disable-interactivity --accept-source-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetUpdater.Out.txt" -RedirectStandardError "$($LogDir)\WinGetUpdater.Warning.txt"
    $updated=0
    $lines=Get-Content -Path "$($LogDir)\WinGetUpdater.Out.txt"
    $lines | ForEach-Object {
        if ($_ -like "*Successfully installed*") {$updated++}
    }
    OutputWriter("$updated packages are updated. Return code of the operation: $($rval.ExitCode)")
}
