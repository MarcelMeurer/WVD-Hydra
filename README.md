# WVD-Hydra



<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FmainTemplate.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FcreateUiDefinition.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a>





## Preview Terms

Project "Hydra" is an upcoming solution to manage Windows Virtual Desktop for one or more tenants. It's currently in preview, which means that it can be tested in some environments without any support nor warranty, at your own risk, and without the right of indemnity. However, I am trying to publish the preview releases in high quality.

The project will be made available in the future as a community edition and as a supported licensable product.

Please make sure to send feedback and update the solution regularly.



## Preview Features

- Multi-tenancy
- Management of user sessions
  - Logoff, messages
- Management of session hosts
  - Start, Stop, Delete, Restart, Automatically change disk types
- Autoscale
  - Multi-Session hosts
    - Power-on-connect support
    - Schedules
    - Autopilot: Automatically scales up/down/create/remove based on the usage of a host pool
    - Deploy hosts on demand - including ephemeral VMs based on a custom image
  - VDI
    - Auto deallocate session hosts
- Session Timeouts
- Session host definitions
  - Per host pool
  - Images and shared images
  - Copy configuration
- Auto Health

  - Remove orphan sessions (not yet configurable)
- ...



## Installation

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FmainTemplate.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FcreateUiDefinition.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a>

Use the "Deploy to Azure" button to roll out your instance of Project Hydra into your subscription. 

During the deployment, you have to enter the following information:

- Basics

- - Subscription
  - Resource group
  - Region
  - Name of your deployment: That name becomes the hostname of the hydra-portal e.g., "myhydrainstance.azurewebsites.net". The name must be unique for some resource types. Press "Tab" to let Azure check the availability of the name

- Service Principal

- - A (web) service principal is needed to let users log in to the hydra-portal website. Create the service principal with the PowerShell script in the Cloud Shell. Copy the following data into the fields: 
  - Application Id
  - The secret of the service principal and Confirm secret.

- Administration

- - Add the UPN of the master administrator into the field. You can add multiple administrators separated with a comma. These users have full access to the solution and can add other users with specific permissions in one of the following updates.

- Tags

- - Are optional to tag the resources

After that, click "Create" to install your instance of Project Hydra into your subscription. The deployment will take some minutes.



## Adding your a tenant

Open your Project Hydra instance in a web browser by entering https://myhydrainstance.azurewebsites.net (myhydrainstance is the name of your deployment from the basic step).

Log in with the user you have entered in the administration step (Administrator(s) of the solution). Note: You can change this setting on the deployed app service -> Configuration -> Application settings -> "config:Administrators")

Click "Tenants" and "Add" to add your first or a new tenant. Next, you need a service principal to give Project Hydra access to the WVD resources in the tenant. A service principal is like a functional account that is used for the Hydra engine to log in and access the resources.



You can use WVDAdmin credentials if you have or create a new service principal:

- Open https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps

- Click "New registration"

- - Enter a name for the service principal, e.g., "svc-Hydra_Engine"
  - Click "Register"

- Click "Certificates & secrets"

- - Click "New client secret"
  - Select an expiration date, e.g., 18 month
  - Click "Add"
  - Directly copy the value (the secret) for later use

- Click "Overview"

- - Copy the following data to configure the service principal in Project Hydra

  - - Directory (tenant) ID -> Tenant id
    - Application (client) ID -> Application id
    - The secret from the previous step -> Secret



Before you complete the configuration in Project Hydra, go to your Azure subscription and add the created service principal with contributor permissions to the subscription or all resource groups containing your WVD environment (VMs, host pools, images, v-net, ...). 



Go back to the configuration and give your new tenant configuration a display name and check "Enabled". You can test the service principal by clicking "Test primary". After that, click "Save". Please reload the website after a few minutes to see your environment in Project Hydra.