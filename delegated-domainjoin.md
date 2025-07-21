# Create a service account for an Active Directory domain-join
Often, session hosts must still be part of an Active Directory domain to host applications depending on an AD environment. To join a host (which means a computer object) to AD, a service account with proper permission is needed.

Never use admin credentials for automating these kinds of tasks, and never store admin credentials in Hydra/WVDAdmin. Instead, use a service account with the least privileges necessary to perform this action.

## Create a service account for the domain join
Open Active Directory Users and Computers and select a proper OU to store the new service account. Right-click -> New -> User

![Administrative units](./media/Hydra-DelegateDomainJoin-01.png)
 
Enter a name for the service account. E.g., “srv-DomainJoin-AVD”

![Add AU](./media/Hydra-DelegateDomainJoin-02.png)
 
Enter a long and complex password for the account and tick both password options (PS: It makes sense to change the password regularly. If so, do this in AD and also in the configuration of Hydra/WVDAdmin).

![Select Cloud Device Administrator](./media/Hydra-DelegateDomainJoin-03.png)
 
Finish the creation of the service account.

![AU view after a minute](./media/Hydra-DelegateDomainJoin-04.png)

## Give the service account delegated permissions for the domain join
After you created one or more OU for your hosts/computer accounts, delegate the permission at the entry level for your computers. In my case, that is AVD-Hosts (I’m using OUs to separate the hosts by their host pools).

![Change membership type](./media/Hydra-DelegateDomainJoin-05.png) 

Right-click -> Delegate Control...

![Add query](./media/Hydra-DelegateDomainJoin-06.png)
 
Next
 
![Select the role](./media/Hydra-DelegateDomainJoin-07.png)

Click on “Add” and select the previously created service account.

![Select the service principal](./media/Hydra-DelegateDomainJoin-09.png)
 
Next, select “Create custom task to delegate”.

![API permissions tab](./media/Hydra-DelegateDomainJoin-10.png)

Select the proper options. Make sure to only do it related to the “Computer objects”:

![Entra device permission](./media/Hydra-DelegateDomainJoin-11.png)

Next. Configure the selected options only:

![Admin consent not given](./media/Hydra-DelegateDomainJoin-12.png)

Next, and finish the delegation.

![Admin consent given](./media/Hydra-DelegateDomainJoin-13.png)

The service account now has the right permissions. Please regularly monitor the usage of the account.

## Add the service account to Hydra
Select properties of the OU where do you want to store the hosts/computer objects.

![Rollout configuration to enable Entra and Intune device deletion](./media/Hydra-DelegateDomainJoin-14.png)
 
Select “Attribute Editor” and double-click on distinguishedName. You can now copy the OU path for later use:

![Example of a device deletion](./media/Hydra-DelegateDomainJoin-15.png)

In Hydra, open the rollout configuration of a host pool and enter the data of the service account, domain, and OU path:

![Example of a device deletion](./media/Hydra-DelegateDomainJoin-16.png)

You are ready to go.