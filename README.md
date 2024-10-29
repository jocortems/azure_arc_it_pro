This repository is a modified version of [Jumpstart ArcBox for IT Pros](https://azurearcjumpstart.io/azure_jumpstart_arcbox/ITPro), it uses Terraform instead of Bicep to deploy the artifacts, and has separate directories for the Azure Arc artifacts and the Nested Virtual Machines that simulate the OnPremises Arc servers, the idea is to be able to deploy each component to different subscriptions and/or Entra Tenants in case one Tenant has restrictions that prevent onboarding of Arc servers to it but has enough budget to deploy the VM that will run the nested VMs, in this case an MSDN subscription can be used to deploy Azure Arc artifacts which incurr minimal consumption. Additionally, this repository doesn't auto-onboard the nested VMs into Arc, this is intentional to have the opportunity to go through the process of onboarding the servers for learning purposes.

Other things that are different in this repository are:

- Azure Policy has 3 initiatives deployed:
    - One for Arc-Enabled SQL servers that deploys Defender for SQL, deploy Best Practices Analysis and onboards servers with the SQL IaaS extension installed to Azure Monitor Agent
    - One for Arc-Enabled Windows servers which deploys Defender for Windows Extension, Change Tracking and Inventory extension, onboard to Log Analytics Workspace using Data Collection Rules
    - One for Arc-Enabled Linux servers which deploys Defender for Linux Extension, Change Tracking and Inventory extension, onboard to Log Analytics Workspace using Data Collection Rules
- [Dashboards](https://github.com/microsoft/sql-server-samples/tree/master/samples/features/azure-arc/dashboard) and [workbooks](https://github.com/microsoft/sql-server-samples/tree/master/samples/features/azure-arc/workbooks) for Arc-Enabled SQL servers are automatically deployed

This repository has two folders as follows:

- onprem-arc: deploys the Azure virtual machine and the nested VMs on top of it, make sure to pass the required variables
- arcbox-it-pro: deploys Azure Arc artifacts (workbooks, dashboards, Azure Policy)