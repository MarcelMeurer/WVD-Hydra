# AVD Hydra & WVD-Hydra



<a href="https://portal.azure.com/#create/itprocloudgmbh1628775137215.hydra-deploy-d1hydra-free-d1" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a>

[Get free support for the deployment](mailto:info@itprocloud.com)



## Terms

"Hydra" is a solution to manage Azure Virtual Desktop (Azure Virtual Desktop) for one or more tenants. It's a working solution and can be installed in any subscription. The solution can be used at your own risk and without the right of indemnity. However, I am trying to publish the preview releases in high quality.

The project is available as a **free community edition, even for commercial use** (up to 6 session hosts per host pool and a single tenant) and as a supported licensable product ($2 per concurrent user/month). Hydra will generally work without limitation for the first 30 days and switched to the community edition. Please reach out to extend the trial period or to get a commercial offer.

The owner of this solution is ITProCloud GmbH, [info@itprocloud.com](mailto:info@itprocloud.com).

Please make sure to send feedback and update the solution regularly.



## Get help

If you are not familiar with the first configuration and creating a service principal in Azure, write us a mail to give you free support: [info@itprocloud.com](mailto:info@itprocloud.com)



## Features

- Multi-tenancy
- Role-based access
- Image management
  - Create images from VMs / Golden Masters without destroying the source VM
  - Copy images to shared image galleries
  - Delete older images or gallery images
  - Deploy session hosts based on images
- Management of user sessions
  - Logoff, messages, shadow user sessions, delete [FSLogix profiles](#Delete-FSLogix-profiles-from-the-user-sessions-menu)
  - In preview: Show user processes, incl. CPU and memory usage; Terminate user processes ([requires an agent](#Install-the-Hydra-Agent))
- Management of session hosts
  - Start, Stop, Delete, Restart, Automatically change disk types
  - Create new session hosts with a click (with classic disks or ephemeral)
  - Create new session hosts directly into the drain-mode
  - Automation scripts and script collections
- Autoscale
  - Multi-Session hosts
    - Power-on-connect support
    - Schedules
    - Autopilot: Automatically scales up/down/create/remove based on the usage of a host pool
    - Deploy hosts on demand - including ephemeral VMs based on a custom image*
    - Delete and rebuild hosts after logoff
  - VDI
    - Auto deallocate session hosts
    - Start spare-host to allow an assign on first connect for new users
    - Create new VDIs if needed based on a custom image*
- Session Timeouts
- Session host definitions for rollouts
  - Per host pool
  - Images and shared images
  - Copy configuration
- Monitoring
  - Shows the storage usage (Azure files, FSLogix profile shares)
- Auto Health
  - Remove orphan sessions*
- Automatic disk change
  - Disk type can automatically be changed on start/deallocation/autoscaling to save storage costs (switch between HDD-Premium-HDD or HDD-SSD-HDD)
- [Scripts and Script Collections](#Scripts-and-Script-Collections)
  - Run Powershell scripts on session hosts
  - Orchestrate hosts with multiple scripts and tasks: Drain mode on -> Logoff users -> Start the VM -> Run a script -> Restart -> Drain mode off
  - Built-in scripts/collections for Windows Update, Windows 10 optimization, ...
- ...

<sup>* Currently not available in the US</sup>



## Updates and releases
Hydra can be easily updated from GitHub. Open the deployed app service -> Deployment Center -> click on "Sync"
- 1.0.1.42	(2022/02/24)
  - Fix: In split tenant mode, the web gui showed the wrong networks (from the primary tenant)
- 1.0.1.41	(2022/02/16)
  - Add: User assignment to a VDI session host can be done directly using the the session host view (add, change or delete assignment)
- 1.0.1.40	(2022/02/15)
  - Change: User and session host list can be downloaded as CSV (showing the content of the displayed table)
- 1.0.1.39	(2022/02/14)
  - Add: More Microsoft marketplace images; Optional and currently experimental*: Notify users to log off and on again to consolidate sessions in multi-session environments (consolidation is then done with the depth-first load balancer) 
- 1.0.1.38	(2022/02/08)
  - Add: Date of the creation of a session host is stored in the database; Change: The load in the host pool view (last 12h) are now stored high efficiently to increase the performance if you have a lot of host pools (50+) - *Note:* The update will reset the 12h charts
- 1.0.1.37	(2022/02/01)
  - Add: Align to the Azure Portal: Don't show error messages with error code != 0 and HealthCheckResult!='HealthCheckSucceeded'
- 1.0.1.36	(2022/01/28)
  - Add: Optionally delete session hosts after a specific time of no use (personal host pools) - use carefully
- 1.0.1.35	(2022/01/21)
  - Add: The last time a connection was seen is now stored on a session host level in the database. This will be used for version 1.0.1.36 to optionally delete session hosts after a specific time of no use
- 1.0.1.34	(2022/01/20)
  - Fix: Deployment of new VDI doesn't started under some conditions
- 1.0.1.33	(2022/01/18)
  - Add: Increase of the time out for an AAD-only deployment (takes much longer to join an AAD instead of an AD)
- 1.0.1.32	(2022/01/13)
  - Add: Improvement to display host-pool tiles on the dashboard (visualization needed an reload to view new host pools); improvement to recognize ephemeral hosts
- 1.0.1.31	(2022/01/07)
  - Fix: In some cases the script engine has not started after a hosts shows an error from the AVD backend
- 1.0.1.30	(2022/01/04)
  - Fix: The process list of a user was sometimes not shown (error message about the JSON data) correctly if the user had a long process list
- 1.0.1.29	(2021/12/16)
  - Fix: Image reference "Windows 10 EVD - Gen2 - 21h2" corrected; Add: New images for 21h2 + Office
- 1.0.1.28	(2021/12/15)
  - Fix: Preview feature "Show process list" doesn't show processes for disconnected users
- 1.0.1.27	(2021/12/07)
  - Preview Feature: Show user processes ([requires an agent](#Install-the-Hydra-Agent))
  - Add: A fix to handle that sometimes the Azure API returns an empty resource id to the VM for a session host
- 1.0.1.25	(2021/11/12)
  - Add: Improvement of the imaging process to avoid that the Azure Agent shows older logs after the rollout of new VMs
  - Add: For the rollout configuration: You can now select the source VM (Golden Master) instead of an image. Hydra will care that always the newest image of the source VM is used for the next rollout
  - Add: Preparation to have unassigned hosts available in a personal host pool  (private preview)
  - Change: Deleting an FSLogix profile from the GUI will no longer remove all files in the profile folder. Only VHD* files will be removed
  - Fix: Remove a typo in the log analytics data column for host pool statistics
- 1.0.1.24	(2021/11/04)
  - Hydra now has the imaging capabilities from WVDAdmin. You can create images based on existing VMs / Golden Masters without destroying them. The VMs / Golden Masters can be updated in the future and captured again
  - Hydra has now a Logging menu item to show the latest operations
  - Concurrent user count is now logged into the log analytics workspace in log Hydra_ConcurrentUserUsage_CL
- 1.0.1.23	(2021/10/22)
  - Add: In some cases, Azure cannot provide specific VM sizes because of insufficient resources. This prevents session hosts from starting or deploying. You can configure now on a host pool level -> New session host rollout -> Advanced setting an alternative VM size. This VM size is then used to deploy new hosts for a specific time. Additionally, if a host cannot start with insufficient resources, the VM size will be changed to the alternative configuration. This will not be undone automatically right now. This function should prevent running into temporary issues. Make sure that the alternative VM size fits the other configuration properties (like disk type). A mapping table to select an alternative VM size in case of an issue automatically is on the roadmap.
- 1.0.1.22	(2021/10/19)
  - Add: Make the rollout of new hosts more reliable (typical download error of the SXS stack files should be handled with a retry)
- 1.0.1.21	(2021/10/14)
  - Fix: If a host upgrades the AVD agent for longer than 5 minutes, the host will be ignored (until the agent is updated correctly); Remove leading and trailing white-space from the OU string
- 1.0.1.20	(2021/10/08)
  - Add: Shows version in the web GUI and link to the marketplace
- 1.0.1.19	(2021/10/06)
  - Add: Installs the extensions for AMD/NVIDIA GPU manually or automated during deployment of hosts (configurable on the host pool level -> New Session Host Rollout)
- 1.0.1.18	(2021/10/05)
  - Add: Logging off users are now awaited. This solve an issue while deleting a FSLogix profile while the logoff process is still running
- 1.0.1.17	(2021/10/03)
  - Add: Showing the current usage of Azure files file shares; Fix: Removing FSLogix profiles will now consider SIDDirNameMatch
- 1.0.1.16	(2021/09/25)
  - Add: Assigned users are now visible in the session host list; additional targets for script / collections schedules (single host, named hosts, ...)
- 1.0.1.15	(2021/09/22)
  - Fix: Optimization to the memory handling for large environments
- 1.0.1.14	(2021/09/13)
  - Fix/Add: Handle option "FlipFlopProfileDirectoryName" for FSLogix profiles
- 1.0.1.13	(2021/09/13)
  - Add: Memory optimization for larger environments
- 1.0.1.12	(2021/09/04)
  - Add: Watchdog for the worker process, improvement of the deployment of Hydra
- 1.0.1.11	(2021/08/26)
  - Fix: If prediction in autoscaling is disabled, under some circumstance, the value "Min. number of available sessions" was ignored
- 1.0.1.10	(2021/08/25)
  - Add: User list shows the disconnected time of users; Add: Azure AD Join + MEM (Intune join) is available
- 1.0.1.9	(2021/08/24)
  - Add: For shared host pools - Autoscaling: Delete and rebuild hosts after logoff - If a rollout profile exists and the last user has logged off from a session host, the session host will be deleted, and a new one will be rolled out (test carefully)
- 1.0.1.8	(2021/08/24)
  - Fix: In some circumstances deallocating a session host shows an error while the host deallocates correctly
- 1.0.1.7	(2021/08/16)
  - Add: Change: Change the rollout process to be more reliable if you deploy a lot of hosts at once; Fix: Secrets can now have special characters
- 1.0.1.6	(2021/08/08)
  - Add: Scripts and script collections can be triggered by schedules on a host pool level (e.g., to automatically update Windows across a host poll Sunday morning, ...)
- 1.0.1.5	(2021/08/05)
  - Add: Scripts and script collections are available to manage session hosts. Can be applied after a rollout of a new host or by selecting session hosts and a script/collection or with a schedule on the host pool level; Fix: Some fine tunings, like session timeouts, performance, etc.
- 1.0.1.4	(2021/07/04)
  - Add: Action log is now repeatable (GUI integration coming soon) and encrypt given secrets
- 1.0.1.3	(2021/07/01)
  - Fix: Change of an icon and rendering of a table in the schedule configuration
- 1.0.1.2	(2021/07/01)
  - Improvement of displaying the time chart in the host pool
- 1.0.1.1	(2021/06/30)
  - Deploy new session host in drain-mode (optional)
- 1.0.1.0	(2021/06/28)
  - Delete [FSLogix profiles](#Delete-FSLogix-profiles-from-the-user-sessions-menu) from the user sessions menu
- 1.0.0.9	(2021/06/24)
  - Deployment tags can be configure on a per host pool level
  - Note: The update removes the temporary stored session statistic for the last 12 hours (once to create an index to show the data faster)
- 1.0.0.8	(2021/06/18)
  - Auto health can be configured on the host pool level for orphan sessions
- 1.0.0.7	(2021/06/17)
  - Bugfix: 'Auto-change disk type' can now be disabled
- 1.0.0.6	(2021/06/16)
  - 'Auto-change disk type' can be configured on the host pool level (base settings) to switch to disks to SSD/Premium on start and HDD after deallocating (saving money for the storage)
  - Autoscale schedules can now include serving a minimum number of free sessions.
- 1.0.0.5	(2021/06/15)
  - Role-base access and mirroring of user sessions (click on the play icon in the user overview of an active session)

<sup>* Currently not available in the US</sup>

## Installation

<a href="https://portal.azure.com/#create/itprocloudgmbh1628775137215.hydra-deploy-d1hydra-free-d1" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a>

Use the "Deploy to Azure" button to roll out your instance of Hydra into your subscription.

<a href="https://youtu.be/GaRrotF0peM" target="_blank">See the installation and basic configuration on YouTube</a>


During the deployment, you have to enter the following information:

- Basics

  - Subscription
  - Resource group
  - Region
  - Name of your deployment: That name becomes the hostname of the hydra-portal e.g., "myhydrainstance.azurewebsites.net". The name must be unique for some resource types. Press "Tab" to let Azure check the availability of the name

- Service Principal

  - A (web) service principal is needed to let users log in to the hydra-portal website. Create the service principal with the PowerShell script in the Cloud Shell. Copy the following data into the fields: 
  - Application Id
  - The secret of the service principal and Confirm secret.

- Administration

  - Add the UPN of the master administrator into the field. You can add multiple administrators separated with a comma. These users have full access to the solution and can add other users with specific permissions in one of the following updates.

- Tags

  - Are optional to tag the resources

After that, click "Create" to install your instance of Project Hydra into your subscription. The deployment will take some minutes.



## Adding a tenant

***Note:** If you are not familiar with the first configuration and creating a service principal in Azure, write us a mail to give you free support: [info@itprocloud.com](mailto:info@itprocloud.com)*

Open your Project Hydra instance in a web browser by entering https://myhydrainstance.azurewebsites.net (myhydrainstance is the name of your deployment from the basic step).

Log in with the user you have entered in the administration step (Administrator(s) of the solution). Note: You can change this setting on the deployed app service -> Configuration -> Application settings -> "config:Administrators")

Click "Tenants" and "Add" to add your first or a new tenant. Next, you need a service principal to give Project Hydra access to the WVD resources in the tenant. A service principal is like a functional account that is used for the Hydra engine to log in and access the resources.



You can use **[WVDAdmin](https://blog.itprocloud.de/Windows-Virtual-Desktop-Admin/)** credentials if you have or create a new service principal:

- Open [https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps](https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps)

- Click "New registration"

  - Enter a name for the service principal, e.g., "svc-Hydra_Engine"
  - Click "Register"

- Click "Certificates & secrets"

  - Click "New client secret"
  - Select an expiration date, e.g., 18 month
  - Click "Add"
  - Directly copy the value (the secret) for later use

- Click "Overview"

  - Copy the following data to configure the service principal in Project Hydra

    - Directory (tenant) ID -> Tenant id
    - Application (client) ID -> Application id
    - The secret from the previous step -> Secret



Before you complete the configuration in Project Hydra, go to your Azure subscription and add the created service principal with contributor permissions to the subscription or all resource groups containing your WVD environment (VMs, host pools, images, v-net, ...). 



Go back to the configuration and give your new tenant configuration a display name and check "Enabled". You can test the service principal by clicking "Test primary". After that, click "Save". Please reload the website after a few minutes to see your environment in Project Hydra.



## Scaling

Scaling can be essential in a WVD environment regarding the costs. For example, running virtual machines costs money - independent if users are connected or not. Additionally, the storage costs 24/7 - even for a deallocated virtual machine. Typically in WVD, the number of user sessions changed from time to time, and in a best-case, the number of running session hosts correspondent to the actual count of user sessions.

Hydra can scale pooled session hosts (multi-session) and persistent (VDI) host pools in a very smart way - like an autopilot for host pools. And: It can create temporary session hosts on demand if needed and delete them later, saving costs for the non-existing virtual disks.



### Scaling of pooled host pools

A pooled host pool should have always had enough running session host to provide capacity to host the upcoming users (but not more) or should use Power-on-Connect to start the first session host while a user begins the connection.

While hydra autoscaling and autoshutdown works perfectly with Power-on-Connect, I recommend [enabling this feature](https://blog.itprocloud.de/Custom-Role-for-Power-On-Connect-Preview/). Additionally, Power-on-Connect allows deallocating all session hosts if no user is connected.



***Dashboard -> Three dots icon (configuration) on the host pool -> Autoscale & Autoshutdown***



Enable the configuration and configure the basic settings:

- Use Power-On-Connect (preview feature):
  Check this (and configure Power-on-Connect) to bring the host pool down to zero session hosts
- Session hosts running 24/7:
  With Power-on-Connect you can go down to 0. If you have reserved instanced, it is a good option to let some session hosts running permanently (users don't have to wait for the start of a session host)
- Default Loadbalancer Type:
  Should be "Depth-First"
- Min. number of available sessions:
  A minimum amount of a free session capacity. If you set it to 5 then always enough session hosts are available to host 5 more sessions. 0 is the most cost-saving value (brings the host pool down to zero session hosts)
- Min. number of hosts without sessions:
  A minimum amount of session hosts without user sessions. 0 is the most cost-saving value (brings the host pool down to zero session hosts)
- Temporarily rollout new session hosts up to a max. number of hosts in the pool:
  If a default rollout profile is configured, autoscale can create new session hosts if needed. This configuration limits the total amount of session hosts in the pool. Temporarily created session hosts will be removed automatically if no longer needed. Note: Power-On-Connect cannot trigger the creation of a new session host
- Concurrent starts/rollout of session hosts at the same time:
  Limits the number of parallel starts/creation of session hosts. In a huger environment, increase this value to start more session hosts at the same time



Additionally, you can configure schedules to have several session hosts running in the peak time of the logons (e.g. between 7:00 am and 9:00 am). Hint: You don't need to cover the working hours - if more session hosts are needed, autoscale will start or create new hosts (like an auto-pilot).



Add a new schedule and configure:

- Min. Hosts:
  The min. number of hosts running in the time frame. If fewer hosts are running, autoscale will start/create additional hosts
- Min. Free Sessions:
  Optionally: Minimum number of available (free) sessions during the schedule. The engine keeps care that enough session hosts are running to handle this number of new sessions (the engine will start additional hosts)
- Weekdays, from, to:
  The time when this schedule is active
- Load-Balancer: 
  You can change the load-balancer type for the time frame to breadth-first to spread the logons around all available session hosts. That increases the performance dramatically in a logon-storm-phase
- Build-First:
  If a default rollout profile is configured, you can use this option to temporarily roll out a new session host to reach the minimum level of hosts for this time frame. Temporarily created session hosts will be removed automatically if no longer needed. Note: This is a great option with Power-on-Connect: Let the engine create 60% of the needed hosts in the morning and left the existing host deallocated for Power-on-Connect
- Note: Configure the time zone of the host pool in the "Base" tab



**Pro-Tip:**

- Create a default rollout profile in the "New session host rollout" tab and test it 
- User Power-on-Connect to bring down the host pools to 0 hosts
- Have several session hosts deployed permanently to (with Hydra or WVDAdmin). These hosts are proposed to start them if new hosts are needed (starting is faster than creating)
- Use a schedule to provide temporarily created hosts in the rush hour (typically in the morning). These hosts will be deleted if no longer needed (and that saves the costs for the non-existing disks as well)
- Configure "Session Timeouts" to log off disconnected sessions



**Pro-Pro-Tip:** 

- Use ephemeral disks for more saving and higher performance)



**Example:**

![](media/Scale-Pooled-01.png)



### Scaling of persistent host pools

A persistent host pool contains assigned session hosts for named users. A user can start the session hosts directly with the WVD client: If the session host is deallocated, a click to the desktop icon will start the session host using the [Power-on-Connect](https://blog.itprocloud.de/Custom-Role-for-Power-On-Connect-Preview/) feature.



To deallocate unused hosts automatically, configure "Autoscale & Autoshutdown" in Hydra:



***Dashboard -> Three dots icon (configuration) on the host pool -> Autoscale & Autoshutdown***



Add a new schedule and configure:

- Timeouts in minutes:
  The time after an unused session host will be deallocated
- Weekdays, from, to:
  The time when this schedule is active
- Note: Configure the time zone of the host pool in the "Base" tab



**Example:**

![](media/Scale-Persistent-01.png)

The example shutdown unused session hosts after 20 minutes for every day and time in a week.

Note: 

- You can add multiple schedules for different times
- Configure "Session Timeouts" to log off disconnected sessions
- Only session hosts without sessions are deallocated after the timeout



## Session timeouts

Session timeouts a very helpful to log off disconnected sessions fast. Disconnected sessions are log out automatically after a timeout. That is important to allow autoscale to deallocate session hosts. You can define different timeouts based on the weekdays and times (like in the example below):



***Dashboard -> Three dots icon (configuration) on the host pool -> Session Timeouts***



Add a new schedule and configure:

- Timeouts in minutes:
  The time after a disconnected session will be deallocated
- Weekdays, from, to:
  The time when this schedule is active
- Note: Configure the time zone of the host pool in the "Base" tab



**Example:**

![](media/SessionTimeouts-01.png)

For the example, disconnected sessions will be logged off:

- Mo-Fr between 7:00 am and 8:00 pm, after 120 minutes (working hours, enough time to have a lunch or a meeting)
- Mo-Fr outside 7:00 am and 8:00, after 20 minutes
- On the weekend, after 20 minutes

Note: 

- You can add multiple schedules for different times
- Session timeouts work for pooled and persistent host pools



## Delete FSLogix profiles from the user sessions menu

Users and administrators with the role ***User and profile manager*** or higher can delete FSLogix profiles in two ways:
- Select the users -> Burger menu ->Delete FSLogix Profile (left)

  - The users are logged off, and the FSLogix profile will be deleted from the storage

- Burger menu ->Delete FSLogix Profile (left)

  - Select a host pool and enter the user names (UPN, e.g., user1@contoso.com;user2@contoso.com) into the text field


In both cases, the profiles are deleted from the storage account. The profile path is read from one available session host in the host pool.

**Prerequisites:**

- Enter a service account of your local AD domain into the basic setting of each host pool where you want to use this feature. The service account is used to authenticate to the storage account, NetApp files, etc., and needs proper permission to delete files.
  - Hint: For Azure Files, give the service account *"Storage File Data SMB Share Elevated Contributor"* permission on the storage account. Note: That can take a while. I made progress after creating one folder on the share in the context of the service account.
- An available session host in the selected host pool

![](media/Delete-FSLogix-01.png)

## Scripts and Script Collections

Scripts and script collections. Both are intended to automize Azure VMs, and Azure Virtual Desktop (AVD) from the management perspective.

### Script

A Powershell script for a session host. The script runs in the system context with system permissions, variables containing data about the host pool, session hosts, etc. Optionally, a Powershell credential object (PSC) can be used to connect to other services, like files shares (the service account can be configured on the host pool level).

![](media/Script-01.png)

### Script Collections

A script collection is a collection of scripts and tasks in any sequence. E.g.: Drain mode on -> Logoff users -> Start the VM -> Run a script -> Restart -> Drain mode off

![](media/ScriptCollection-01.png)

Additionally, parameters can be set for a script, and error handling is built-in. Script collections are very useful to orchestrate several tasks and scripts to session hosts.

### Built-in scripts and collections

There are several built-in scripts and collections, and new scripts and collections are provided continuously. Built-in scripts can be updated with the "Update" button in the upper-right corner.

![](media/ScriptCollectionSync-01.png)



To add a custom script or script collection, copy the *"BuiltIn: 1st Template Script"* or *"BuiltIn: 1st Template Script Collection"*. Then start building the new one. Make sure to save the new script/collection with a click of the disk symbol. There is no warning right now if you close the browser or if you navigate to another site.

![](media/ScriptCollectionSaveBar-01.png)



### Triggering a script or script collection

Scripts and script collections can be triggered by *Host pool administrators* and edited by *Full administrators*.

Both can be assigned/triggered in different ways:

#### For selected hosts

![](media/ScriptCollectionAssign-SessionHosts-01.png)

#### Automatically after the rollout of a new session host

![](media/ScriptCollectionAssign-Rollout-01.png)

#### By a schedule

Schedules can be used on a host pool level to run a script or collection unattended on session hosts of the pool. Comparable to other schedules, weekday(s) and start time define the plan. The following parameters can be used to fine-tune the schedule:

- Hosts

- - Run on all hosts
  - Run only on hosts without user sessions
  - Run only on hosts in drain-mode

- Simultaneously

- - Starts directly on all hosts
  - Start on max. 5 session hosts at the same time (if one finished, the script/collection will be started on the next host)
  - ...

![](media/ScriptCollectionAssign-Schedule-01.png)

This example runs Windows Update on all session hosts Sunday, 1:00 am. Including drain mode, start, update, restart, drain mode off.

### Install the Hydra Agent

The Hydra Agent is currently in preview and is only needed for a small feature set. Today, it's required to show user processes in the user session list and maybe terminate user processes in case of an issue.

#### Prepare the installation of the Hydra Agent

- Create a new collection by copying an existing one
- Change the name and description to "Install Hydra Agent"
- Clear the collection and add one step: "VM - Deploy Hydra Agent"
- Save the new collection

Hint: If your Hydra instance has another external name then myinstance.azurewebsites.net, you can set the external name as a parameter of the step in the collection 

![](media/HydraAgent-01.png)

#### Enable Websockets on the app service

- Open the app service of your Hydra instance in the Azure Portal
- Go to: Configuration -> General settings -> Set Web sockets to On
- Click "Save" (your Hydra instance will restart)

![](media/HydraAgent-02.png)

#### Deploy the agent to session hosts

Open a host pool where you want to run the agent. 

- Select the hosts
- Click in the burger menu "Start a script or collection"
- Select "Install Hydra Agent" and click "Ok"

Hint: You can run "Install Hydra Agent" with the image creation process on the Golden Master. All deployed session hosts based on this master will have the Agent installed, and you can directly use the advanced features.

![](media/HydraAgent-03.png)

#### Showing user processes

If the Hydra Agent is installed on session hosts, the processes of a single user can be shown in the "User sessions" menu. Click on the icon right to the user to show the processes.

![](media/HydraAgent-04.png)

