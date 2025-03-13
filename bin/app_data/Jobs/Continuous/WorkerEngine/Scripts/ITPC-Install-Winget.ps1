# This powershell script is part of Hydra
# Current Version of this script: 2.2

param(
	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
	[ValidateSet('InstallApps','UpdateAllApps')]
	[string] $Mode,
    [string] $Apps64 = ''              # Used in InstallApps and UpdateAllApps (empty means updating all apps, otherwise comma separated list of Ids)
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

# Source: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
$wgetErrorCodes = @{
    "-1978335231" = "Internal Error"
    "-1978335230" = "Invalid command line arguments"
    "-1978335229" = "Executing command failed"
    "-1978335228" = "Opening manifest failed"
    "-1978335227" = "Cancellation signal received"
    "-1978335226" = "Running ShellExecute failed"
    "-1978335225" = "Cannot process manifest. The manifest version is higher than supported. Please update the client."
    "-1978335224" = "Downloading installer failed"
    "-1978335223" = "Cannot write to index; it is a higher schema version"
    "-1978335222" = "The index is corrupt"
    "-1978335221" = "The configured source information is corrupt"
    "-1978335220" = "The source name is already configured"
    "-1978335219" = "The source type is invalid"
    "-1978335218" = "The MSIX file is a bundle, not a package"
    "-1978335217" = "Data required by the source is missing"
    "-1978335216" = "None of the installers are applicable for the current system"
    "-1978335215" = "The installer file's hash does not match the manifest"
    "-1978335214" = "The source name does not exist"
    "-1978335213" = "The source location is already configured under another name"
    "-1978335212" = "No packages found"
    "-1978335211" = "No sources are configured"
    "-1978335210" = "Multiple packages found matching the criteria"
    "-1978335209" = "No manifest found matching the criteria"
    "-1978335208" = "Failed to get Public folder from source package"
    "-1978335207" = "Command requires administrator privileges to run"
    "-1978335206" = "The source location is not secure"
    "-1978335205" = "The Microsoft Store client is blocked by policy"
    "-1978335204" = "The Microsoft Store app is blocked by policy"
    "-1978335203" = "The feature is currently under development. It can be enabled using winget settings."
    "-1978335202" = "Failed to install the Microsoft Store app"
    "-1978335201" = "Failed to perform auto complete"
    "-1978335200" = "Failed to initialize YAML parser"
    "-1978335199" = "Encountered an invalid YAML key"
    "-1978335198" = "Encountered a duplicate YAML key"
    "-1978335197" = "Invalid YAML operation"
    "-1978335196" = "Failed to build YAML doc"
    "-1978335195" = "Invalid YAML emitter state"
    "-1978335194" = "Invalid YAML data"
    "-1978335193" = "LibYAML error"
    "-1978335192" = "Manifest validation succeeded with warning"
    "-1978335191" = "Manifest validation failed"
    "-1978335190" = "Manifest is invalid"
    "-1978335189" = "No applicable update found"
    "-1978335188" = "winget upgrade --all completed with failures"
    "-1978335187" = "Installer failed security check"
    "-1978335186" = "Download size does not match expected content length"
    "-1978335185" = "Uninstall command not found"
    "-1978335184" = "Running uninstall command failed"
    "-1978335183" = "ICU break iterator error"
    "-1978335182" = "ICU casemap error"
    "-1978335181" = "ICU regex error"
    "-1978335180" = "Failed to install one or more imported packages"
    "-1978335179" = "Could not find one or more requested packages"
    "-1978335178" = "Json file is invalid"
    "-1978335177" = "The source location is not remote"
    "-1978335176" = "The configured rest source is not supported"
    "-1978335175" = "Invalid data returned by rest source"
    "-1978335174" = "Operation is blocked by Group Policy"
    "-1978335173" = "Rest API internal error"
    "-1978335172" = "Invalid rest source url"
    "-1978335171" = "Unsupported MIME type returned by rest API"
    "-1978335170" = "Invalid rest source contract version"
    "-1978335169" = "The source data is corrupted or tampered"
    "-1978335168" = "Error reading from the stream"
    "-1978335167" = "Package agreements were not agreed to"
    "-1978335166" = "Error reading input in prompt"
    "-1978335165" = "The search request is not supported by one or more sources"
    "-1978335164" = "The rest API endpoint is not found."
    "-1978335163" = "Failed to open the source."
    "-1978335162" = "Source agreements were not agreed to"
    "-1978335161" = "Header size exceeds the allowable limit of 1024 characters. Please reduce the size and try again."
    "-1978335160" = "Missing resource file"
    "-1978335159" = "Running MSI install failed"
    "-1978335158" = "Arguments for msiexec are invalid"
    "-1978335157" = "Failed to open one or more sources"
    "-1978335156" = "Failed to validate dependencies"
    "-1978335155" = "One or more package is missing"
    "-1978335154" = "Invalid table column"
    "-1978335153" = "The upgrade version is not newer than the installed version"
    "-1978335152" = "Upgrade version is unknown and override is not specified"
    "-1978335151" = "ICU conversion error"
    "-1978335150" = "Failed to install portable package"
    "-1978335149" = "Volume does not support reparse points."
    "-1978335148" = "Portable package from a different source already exists."
    "-1978335147" = "Unable to create symlink, path points to a directory."
    "-1978335146" = "The installer cannot be run from an administrator context."
    "-1978335145" = "Failed to uninstall portable package"
    "-1978335144" = "Failed to validate DisplayVersion values against index."
    "-1978335143" = "One or more arguments are not supported."
    "-1978335142" = "Embedded null characters are disallowed for SQLite"
    "-1978335141" = "Failed to find the nested installer in the archive."
    "-1978335140" = "Failed to extract archive."
    "-1978335139" = "Invalid relative file path to nested installer provided."
    "-1978335138" = "The server certificate did not match any of the expected values."
    "-1978335137" = "Install location must be provided."
    "-1978335136" = "Archive malware scan failed."
    "-1978335135" = "Found at least one version of the package installed."
    "-1978335134" = "A pin already exists for the package."
    "-1978335133" = "There is no pin for the package."
    "-1978335132" = "Unable to open the pin database."
    "-1978335131" = "One or more applications failed to install"
    "-1978335130" = "One or more applications failed to uninstall"
    "-1978335129" = "One or more queries did not return exactly one match"
    "-1978335128" = "The package has a pin that prevents upgrade."
    "-1978335127" = "The package currently installed is the stub package"
    "-1978335126" = "Application shutdown signal received"
    "-1978335125" = "Failed to download package dependencies."
    "-1978335124" = "Failed to download package. Download for offline installation is prohibited."
    "-1978335123" = "A required service is busy or unavailable. Try again later."
    "-1978335122" = "The guid provided does not correspond to a valid resume state."
    "-1978335121" = "The current client version did not match the client version of the saved state."
    "-1978335120" = "The resume state data is invalid."
    "-1978335119" = "Unable to open the checkpoint database."
    "-1978335118" = "Exceeded max resume limit."
    "-1978335117" = "Invalid authentication info."
    "-1978335116" = "Authentication method not supported."
    "-1978335115" = "Authentication failed."
    "-1978335114" = "Authentication failed. Interactive authentication required."
    "-1978335113" = "Authentication failed. User cancelled."
    "-1978335112" = "Authentication failed. Authenticated account is not the desired account."
    "-1978335111" = "Repair command not found."
    "-1978335110" = "Repair operation is not applicable."
    "-1978335109" = "Repair operation failed."
    "-1978335108" = "The installer technology in use doesn't support repair."
    "-1978335107" = "Repair operations involving administrator privileges are not permitted on packages installed within the user scope."
    "-1978335106" = "The SQLite connection was terminated to prevent corruption."
    "-1978335105" = "Failed to get Microsoft Store package catalog."
    "-1978335104" = "No applicable Microsoft Store package found from Microsoft Store package catalog."
    "-1978335103" = "Failed to get Microsoft Store package download information."
    "-1978335102" = "No applicable Microsoft Store package download information found."
    "-1978335101" = "Failed to retrieve Microsoft Store package license."
    "-1978335100" = "The Microsoft Store package does not support download command."
    "-1978335099" = "Failed to retrieve Microsoft Store package license. The Microsoft Entra Id account does not have required privilege."
    "-1978335098" = "Downloaded zero byte installer; ensure that your network connection is working properly."
    "-1978334975" = "Application is currently running. Exit the application then try again."
    "-1978334974" = "Another installation is already in progress. Try again later."
    "-1978334973" = "One or more file is being used. Exit the application then try again."
    "-1978334972" = "This package has a dependency missing from your system."
    "-1978334971" = "There's no more space on your PC. Make space, then try again."
    "-1978334970" = "There's not enough memory available to install. Close other applications then try again."
    "-1978334969" = "This application requires internet connectivity. Connect to a network then try again."
    "-1978334968" = "This application encountered an error during installation. Contact support."
    "-1978334967" = "Restart your PC to finish installation."
    "-1978334966" = "Installation failed. Restart your PC then try again."
    "-1978334965" = "Your PC will restart to finish installation."
    "-1978334964" = "You cancelled the installation."
    "-1978334963" = "Another version of this application is already installed."
    "-1978334962" = "A higher version of this application is already installed."
    "-1978334961" = "Organization policies are preventing installation. Contact your admin."
    "-1978334960" = "Failed to install package dependencies."
    "-1978334959" = "Application is currently in use by another application."
    "-1978334958" = "Invalid parameter."
    "-1978334957" = "Package not supported by the system."
    "-1978334956" = "The installer does not support upgrading an existing package."
    "-1978334955" = "Installation failed with installer custom error."
    "-1978334719" = "The Apps and Features Entry for the package could not be found."
    "-1978334718" = "The install location is not applicable."
    "-1978334717" = "The install location could not be found."
    "-1978334716" = "The hash of the existing file did not match."
    "-1978334715" = "File not found."
    "-1978334714" = "The file was found but the hash was not checked."
    "-1978334713" = "The file could not be accessed."
    "-1978286079" = "The configuration file is invalid."
    "-1978286078" = "The YAML syntax is invalid."
    "-1978286077" = "A configuration field has an invalid type."
    "-1978286076" = "The configuration has an unknown version."
    "-1978286075" = "An error occurred while applying the configuration."
    "-1978286074" = "The configuration contains a duplicate identifier."
    "-1978286073" = "The configuration is missing a dependency."
    "-1978286072" = "The configuration has an unsatisfied dependency."
    "-1978286071" = "An assertion for the configuration unit failed."
    "-1978286070" = "The configuration was manually skipped."
    "-1978286069" = "A warning was thrown and the user declined to continue execution."
    "-1978286068" = "The dependency graph contains a cycle which cannot be resolved."
    "-1978286067" = "The configuration has an invalid field value."
    "-1978286066" = "The configuration is missing a field."
    "-1978286065" = "Some of the configuration units failed while testing their state."
    "-1978286064" = "Configuration state was not tested."
    "-1978286063" = "The configuration unit failed getting its properties."
    "-1978286062" = "The specified configuration could not be found."
    "-1978286061" = "Parameter cannot be passed across integrity boundary."
    "-1978285823" = "The configuration unit was not installed."
    "-1978285822" = "The configuration unit could not be found."
    "-1978285821" = "Multiple matches were found for the configuration unit specify the module to select the correct one."
    "-1978285820" = "The configuration unit failed while attempting to get the current system state."
    "-1978285819" = "The configuration unit failed while attempting to test the current system state."
    "-1978285818" = "The configuration unit failed while attempting to apply the desired state."
    "-1978285817" = "The module for the configuration unit is available in multiple locations with the same version."
    "-1978285816" = "Loading the module for the configuration unit failed."
    "-1978285815" = "The configuration unit returned an unexpected result during execution."
    "-1978285814" = "A unit contains a setting that requires the config root."
    "-1978285813" = "Loading the module for the configuration unit failed because it requires administrator privileges to run."
    "-1978285812" = "Operation is not supported by the configuration processor."
    "0" = "Done."
}

LogWriter("Microsoft Package Manager Installer")

$startTimeString=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHHmmss")


$folder=@(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" -Force -ErrorAction Ignore| Sort-Object -Property LastWriteTime -Descending)
if ($folder.count -eq 0 -or ($folder[0].VersionInfo.FileVersionRaw.Major -eq 1 -and $folder[0].VersionInfo.FileVersionRaw.Minor -le 19)) {
    LogWriter("Downloading Microsoft Package Manager / Winget")
    DownloadFile "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" "$($env:temp)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
	Add-AppxProvisionedPackage -Online -PackagePath "$($env:temp)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense 
}
$folder=@(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" -Force -ErrorAction Ignore| Sort-Object -Property LastWriteTime -Descending)
$winGetPath=Convert-Path $folder[0].PSParentPath



if ($mode -eq "InstallApps") {
    $apps=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Apps64));
    $appsObj=$apps|ConvertFrom-Json
    $appInstalled=""
    $appWasInstalled=""
    $appCouldntInstalled=""
    $appsObj | Sort-Object -Property Order | ForEach-Object {
        LogWriter("Installing $($_.Name)")
        $rval=Start-Process -PassThru -FilePath "$($winGetPath)\WinGet.exe" -Wait -ArgumentList "install `"$($_.Id)`" --verbose --disable-interactivity  --accept-source-agreements --accept-package-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetInstaller.$($startTimeString).$($_.Id).Out.txt" -RedirectStandardError "$($LogDir)\WinGetInstaller.$($startTimeString).$($_.Id).Warning.txt"
        # one retry
        if (($rval.ExitCode -ne -1978335189) -and ($rval.ExitCode -ne 0)) {
            LogWriter("Installing $($_.Name) - again")
            $rval=Start-Process -PassThru -FilePath "$($winGetPath)\WinGet.exe" -Wait -ArgumentList "install `"$($_.Id)`" --verbose --disable-interactivity  --accept-source-agreements --accept-package-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetInstaller.$($startTimeString).$($_.Id).Out.txt" -RedirectStandardError "$($LogDir)\WinGetInstaller.$($startTimeString).$($_.Id).Warning.txt"
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
            $errMessage=""
            $errMessage=$wgetErrorCodes["$($rval.ExitCode)"]
            LogWriter("There was an issue installing the application $($_.Name). Return value is $($errMessage)")
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
    if ($Apps64 -eq "") {
        LogWriter("Updating all apps on the local host")
        $rval=Start-Process -PassThru -FilePath "$($winGetPath)\WinGet.exe" -Wait -ArgumentList "upgrade --all --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetUpdater.$($startTimeString).Out.txt" -RedirectStandardError "$($LogDir)\WinGetUpdater.$($startTimeString).Warning.txt"
    } else {
        $apps=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Apps64));
        $apps.split(",") | ForEach-Object {
            LogWriter("Updating $_")
            "Updating $_" | Out-File "$($LogDir)\WinGetUpdater.$($startTimeString).Out.txt" -Append
            "Updating $_" | Out-File "$($LogDir)\WinGetUpdater.$($startTimeString).Warning.txt" -Append
            $rval=Start-Process -PassThru -FilePath "$($winGetPath)\WinGet.exe" -Wait -ArgumentList "upgrade $_ --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --source winget" -RedirectStandardOutput "$($LogDir)\WinGetUpdater.$($startTimeString).x.Out.txt" -RedirectStandardError "$($LogDir)\WinGetUpdater.$($startTimeString).x.Warning.txt"
            LogWriter("Status of updating $_ : "+$wgetErrorCodes["$($rval.ExitCode)"])
            Get-Content "$($LogDir)\WinGetUpdater.$($startTimeString).x.Out.txt" | Add-Content -Path "$($LogDir)\WinGetUpdater.$($startTimeString).Out.txt"
            Get-Content "$($LogDir)\WinGetUpdater.$($startTimeString).x.Warning.txt" | Add-Content -Path "$($LogDir)\WinGetUpdater.$($startTimeString).Warning.txt"
            Remove-Item -Path "$($LogDir)\WinGetUpdater.$($startTimeString).x.Out.txt" -ErrorAction SilentlyContinue
            Remove-Item -Path "$($LogDir)\WinGetUpdater.$($startTimeString).x.Warning.txt" -ErrorAction SilentlyContinue
        }
    }

    $updated=0
    $lines=Get-Content -Path "$($LogDir)\WinGetUpdater.$($startTimeString).Out.txt"
    $lines | ForEach-Object {
        if ($_ -like "*Successfully installed*") {$updated++}
    }
    $errMessage=""
    $errMessage=$wgetErrorCodes["$($rval.ExitCode)"]
    if ($errMessage -eq $null -or $errMessage -eq "") {
        $errMessage="$($rval.ExitCode)"
    }
    OutputWriter("$updated packages are updated. Return code of the last operation: $($errMessage)")
}