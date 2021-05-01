<script>
function GetURLParameter(sParam)
{
    var sPageURL = window.location.search.substring(1);
    var sURLVariables = sPageURL.split('&');
    for (var i = 0; i < sURLVariables.length; i++) 
    {
        var sParameterName = sURLVariables[i].split('=');
        if (sParameterName[0] == sParam) 
        {
            return sParameterName[1];
        }
    }
}
</script>

<script>document.write(GetURLParameter("redirectUri"));</script>

#Service principal for the web application

Run the following PowerShell script in the Azure integrated Cloud Shell

```
Invoke-Command {  
$AppName="svc-HydraWebAuthentication-Test5"
$ReplyUri="```
<script>document.write(GetURLParameter("redirectUri"));</script>
```"

Connect-AzureAD
$App=New-AzureADApplication -DisplayName $AppName -GroupMembershipClaims "SecurityGroup" -AvailableToOtherTenants $true -ReplyUrls $ReplyUri
$AppSecret = New-AzureADApplicationPasswordCredential -ObjectId $App.ObjectId -EndDate ([System.DateTime]::Now.AddYears(2).ToString("o"))

write-host "-----------------------------------------------"
write-host "Application Id:        $($app.AppId)"
write-host "Secret:                $($AppSecret.Value)"
write-host "-----------------------------------------------"
}
```



