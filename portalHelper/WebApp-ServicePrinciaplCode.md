# Service principal for the web application

Run the following PowerShell script in the Azure integrated Cloud Shell. Change the variable $ReplyUrl to fits your deployment (mywebsite.azurewebsites.net)

```powershell
Invoke-Command {  
$AppName="svc-HydraWebAuthentication-Test5"
$ReplyUri="https://mywebsite.azurewebsites.net/signin-oidc"
$RequiredGrants = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]::new("00000003-0000-0000-c000-000000000000",@([Microsoft.Open.AzureAD.Model.ResourceAccess]::new("e1fe6dd8-ba31-4d61-89e7-88639da4683d","Scope"),[Microsoft.Open.AzureAD.Model.ResourceAccess]::new("b340eb25-3456-403f-be2f-af7a0d370277","Scope")))

Connect-AzureAD

$App=New-AzureADApplication -DisplayName $AppName -GroupMembershipClaims "SecurityGroup" -AvailableToOtherTenants $true -ReplyUrls $ReplyUri -RequiredResourceAccess $RequiredGrants
$AppSecret = New-AzureADApplicationPasswordCredential -ObjectId $App.ObjectId -EndDate ([System.DateTime]::Now.AddYears(2).ToString("o"))
write-host "--------------------------------------------------------------------------"
write-host "Application Id:        $($app.AppId)"
write-host "Secret:                $($AppSecret.Value)"
write-host "--------------------------------------------------------------------------"}
```



