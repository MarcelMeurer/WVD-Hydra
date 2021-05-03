# WVD-Hydra

**Use this solution on invitation only.**



<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FmainTemplate.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FMarcelMeurer%2FWVD-Hydra%2Fmain%2Fdeployment%2FcreateUiDefinition.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a>





## Preview Terms

Project "Hydra" is an upcoming solution to manage Windows Virtual Desktop for one or more tenants. It's currently in preview, which means that it can be tested in some environments without any support nor warranty, at your own risk, and without the right of indemnity. However, I am trying to publish the preview releases in high quality.

The project will be made available in the future as a community edition and as a supported licensable product.

Please make sure to send feedback and update the solution regularly.



## Preview Features

- Multi-tenancy

- Management of user sessions

- - Logoff, messages

- Management of session hosts

- - Start, Stop, Delete, Restart, Automatically change disk types

- Autoscale

- - Multi-Session hosts

  - - Power-on-connect support
    - Schedules
    - Deploy hosts on demand

  - VDI

  - - (this week): Auto deallocate session hosts)

- Session Timeouts

- Session host definitions

- - Per host pool
  - Copy

- Auto Health

  - Remove orphan sessions (not yet configurable)

- ...