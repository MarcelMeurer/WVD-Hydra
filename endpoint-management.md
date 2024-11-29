# Endpoint Management (preview feature)

## Preview
Endpoint management is a preview feature and may change in further versions. Endpoint management allows the administration of Windows 10 & 11 clients. The clients only need an internet connection and the Hydra Agent for Endpoints. 
This feature must be enabled in the Global settings => Enable Endpoint Management. Please reload the entire website after saving the settings.
Additionally: Enable web sockets for your installation: [Documentation - Hydra Agent - Preconditions](https://github.com/MarcelMeurer/WVD-Hydra#precondition)

## Purpose
Hydra can support customers in managing their endpoints (Windows 10 and 11) simply, easily, and in real time. The endpoints don't need to be enrolled in Intune. If endpoints are enrolled in Intune, Hydras' endpoint management can be used to remotely trigger a sync of the Intune agent or a restart of the agent. Both can help to speed up an application installation.

## Features
To manage endpoints, the Hydra agent needs to be installed. Today, only full administrators have permission to work with the endpoints. This will be changed in the future.

Today, the following features are available:
- Show running processes
- Terminate processes remotely
- Shutdown
- Restart
- Remove App registrations (deletes the key HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\00000000-0000-0000-0000-000000000000
- Sync with Intune
- Restart Intune service
- Run script (a script from the Hydra script collection)
- Update Hydra agent

## Installation
- Download the agent from your Hydra instance: https://&lt;your-instance&gt;.azurewebsites.net/helpers/HydraAgent.zip
- Get the secret for the Hydra agent in the Hydra portal: Endpoints -> Get the secret for the Hydra Agent
- Bring the HydraAgent.exe into a folder on the endpoints (e.g.: C:\Program Files\ITProCloud GmbH\Hydra Agent for Endpoints)
- Start the installation with admin permissions:
  *HydraAgent.exe -u wss://&lt;your-instance&gt;.azurewebsites.net/wsx -s &lt;YourHydraAgentSecret&gt; --EndpointMode -i*

*Tip:* Deploy the Hydra Agent with Intune, if available.

Some actions on the endpoints must be enabled. Set the following reg values to allow the specific actions:
Set-RegistryKey -Key Path: HKLM\SOFTWARE\ITProCloud\HydraAgent

- Allow remote update of the agent
 Allow-UpdateAgent, DWord, Value 1
- Allow remote reboot of the endpoint
 Allow-Reboot, DWord, Value 1
- Allow remote shutdown of the endpoint
 Allow-Shutdown, DWord, Value 1
- Allow remote running a script on the endpoint
 Allow-RunScript, DWord, Value 1




