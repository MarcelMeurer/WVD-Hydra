# Service principal for the web application

Run the following PowerShell script in the Azure integrated Cloud Shell. Change the variable $ReplyUrl to fits your deployment (mywebsite.azurewebsites.net)

```powershell
Invoke-Command {  
$AppName="svc-HydraWebAuthentication-Test5"
$ReplyUri="https://mywebsite.azurewebsites.net/signin-oidc"

Connect-AzureAD
$App=New-AzureADApplication -DisplayName $AppName -GroupMembershipClaims "SecurityGroup" -AvailableToOtherTenants $true -ReplyUrls $ReplyUri
$AppSecret = New-AzureADApplicationPasswordCredential -ObjectId $App.ObjectId -EndDate ([System.DateTime]::Now.AddYears(2).ToString("o"))

write-host "-----------------------------------------------"
write-host "Application Id:        $($app.AppId)"
write-host "Secret:                $($AppSecret.Value)"
write-host "-----------------------------------------------"
}
```



