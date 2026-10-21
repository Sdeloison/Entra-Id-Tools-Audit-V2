# Deployment

Deployment is an explicit operator workflow. CI validates files only. Use a dedicated resource group; do not place unrelated resources or production workloads in it.

## Prerequisites

- Azure CLI with Bicep, PowerShell 7.2+, and the exact Azure Automation module versions in `config/automation-modules.json` (including Az.ResourceGraph and Microsoft.Graph.Authentication).
- An approved Azure subscription and resource group. The deployer needs resource deployment and role-assignment permissions; these are bootstrap permissions, not runtime permissions.
- Separately approved Entra application registrations for the dashboard and Graph managed-identity permissions. No app registration, secret, consent, public endpoint, or schedule is silently created by deployment.

## Review and deploy

```powershell
$subscriptionId = '<SUBSCRIPTION_ID>'
$resourceGroup = '<DEDICATED_RESOURCE_GROUP>'
az login
az account set --subscription $subscriptionId
az group create --name $resourceGroup --location '<REGION>'

.\scripts\Deploy.ps1 -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -Location '<REGION>' -WhatIf
# Review output. Deployment requires this separate explicit action:
.\scripts\Deploy.ps1 -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -Location '<REGION>' -Deploy
```

The script validates/compiles Bicep and runs `az deployment group what-if` before deployment. The Bicep creates the Automation account, user-assigned identity, private report container, and authenticated-dashboard hosting resources. It does not create a schedule or initiate tenant collection.

## Configure and run

1. Inspect deployment outputs; record Automation account, identity, storage, container, and App Service names.
2. Configure Microsoft Graph application permissions explicitly as described in [permissions](permissions.md). Use the script preview first; obtain approved admin consent separately.
3. Assign Azure Reader on only the selected subscriptions. Use `config/default.json` as a local values template; the current runbook receives tenant ID, subscription IDs, storage, and limits as explicit runbook parameters (there is no implicit config-file or Automation-variable loader).
4. Import pinned modules from PowerShell Gallery (the exact versions are recorded in `config/automation-modules.json`):

   ```powershell
   $account = '<AUTOMATION_ACCOUNT>'
   New-AzAutomationModule -ResourceGroupName $resourceGroup -AutomationAccountName $account -Name Az -ContentLinkUri 'https://www.powershellgallery.com/api/v2/package/Az/16.4.0'
   New-AzAutomationModule -ResourceGroupName $resourceGroup -AutomationAccountName $account -Name Microsoft.Graph.Authentication -ContentLinkUri 'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/2.25.0'
   ```

   Wait for both module imports to complete successfully. The repository-local collector modules are concatenated into a temporary, syntax-checked runbook for Automation; temporary source is removed after import. Import the runbook draft first:

   ```powershell
   .\scripts\Publish-Runbook.ps1 -ResourceGroupName $resourceGroup -AutomationAccountName $account
   ```

   Associate the draft with the **PowerShell-7.2** runtime environment in the Automation Runtime Environment experience and confirm the selected runtime. `Import-AzAutomationRunbook` does not choose the runtime environment. After review, publish the already-imported draft:

   ```powershell
   .\scripts\Publish-Runbook.ps1 -ResourceGroupName $resourceGroup -AutomationAccountName $account -Publish
   ```

5. Configure dashboard Entra SPA registration, redirect URI, group claim, tenant/client/audience settings, and reader group. Set the App Service's non-secret settings, then deploy the app package:

   ```powershell
   az webapp config appsettings set --resource-group $resourceGroup --name '<DASHBOARD_APP>' --settings DASHBOARD_TENANT_ID='<TENANT_ID>' DASHBOARD_CLIENT_ID='<SPA_CLIENT_ID>' DASHBOARD_AUDIENCE='api://<API_CLIENT_ID>' DASHBOARD_ALLOWED_GROUP_ID='<READER_GROUP_ID>'
   Push-Location .\src\dashboard
   npm ci --omit=dev
   Compress-Archive -Path .\* -DestinationPath ..\..\dashboard.zip -Force
   Pop-Location
   az webapp deploy --resource-group $resourceGroup --name '<DASHBOARD_APP>' --src-path .\dashboard.zip --type zip
   Remove-Item .\dashboard.zip
   ```

   Confirm the public shell only offers sign-in, unauthenticated API calls return 401, wrong-group tokens return 403, and an authorized reader can load reports.
6. Run a manual job and inspect coverage status, warnings, and report path:

   ```powershell
   $runParameters = @{
     TenantId = '<TENANT_ID>'
     StorageAccountName = '<STORAGE_ACCOUNT>'
     ReportContainer = 'audit-reports'
     SubscriptionIds = @('<SUBSCRIPTION_ID>')
     LookbackDays = 30
     UserAssignedIdentityClientId = '<COLLECTOR_UAMI_CLIENT_ID>'
   }
   .\scripts\Invoke-ManualAudit.ps1 -ResourceGroupName $resourceGroup -AutomationAccountName $account -RunbookName 'Invoke-EntraTenantAudit' -Parameters $runParameters
   ```

7. Only after successful review, create and enable a schedule. The script requires typed confirmation:

   ```powershell
   .\scripts\Set-AuditSchedule.ps1 -ResourceGroupName $resourceGroup -AutomationAccountName $account -RunbookName 'Invoke-EntraTenantAudit' -ScheduleName 'EntraTenantAuditDaily' -StartTime (Get-Date).AddHours(1) -DayInterval 1 -TimeZone 'UTC' -Parameters $runParameters -Enable
   ```

   Document the schedule owner and disable procedure.

### PowerShell runtime support note

This repository preserves the requested PowerShell 7.2 target, but Microsoft currently marks PowerShell 7.2 as out of support and recommends supported Azure Automation runtimes such as PowerShell 7.4 or 7.6. Treat 7.2 as a compatibility constraint, not a long-term production recommendation. Before rollout, validate the pinned Az and Graph modules in the selected Automation runtime; plan and test a move to a supported runtime. See [Azure Automation runbook types](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types) and [runtime environments](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview).

## GitHub repository setup

For an empty private repository:

```text
git init
git add .
git commit -m "Add read-only Entra tenant audit"
git branch -M main
git remote add origin https://github.com/OWNER/REPO.git
git push -u origin main
```

Never place a token in the remote URL. CI uses read-only GitHub token permissions, runs static/unit validation only, and does not deploy or grant consent. If deployment automation is later added, use Azure workload identity federation, a protected GitHub environment, required reviewers, and a narrowly scoped deployment identity. Do not introduce a long-lived publish secret.

## Platform references

Re-check endpoint permissions and module compatibility before production rollout:

- [Azure Automation runbook managed identity](https://learn.microsoft.com/en-us/azure/automation/learn/powershell-runbook-managed-identity)
- [Grant Graph API permissions to managed identities](https://learn.microsoft.com/en-us/powershell/entra-powershell/grant-api-permissions-managed-identity)
- [List Conditional Access policies (Graph v1.0)](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-1.0)
- [Conditional Access results in sign-in logs](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/how-to-view-applied-conditional-access-policies)
- [PowerShell module compatibility](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/module-compatibility?view=powershell-7.2)
- [Graph PowerShell 2.26+ Azure Automation compatibility note](https://devblogs.microsoft.com/microsoft365dev/resolving-microsoft-graph-powershell-2-26-compatibility-issues-with-azure-runbooks/)

## Rollback and teardown

Disable the Automation schedule first. Preserve/export reports according to retention policy. Review the dedicated resource group's resource list, then use `scripts/Remove-Deployment.ps1 -ResourceGroupName <name> -ExpectedTagValue EntraTenantAudit -WhatIf`; execute only after confirming every resource in the group is owned by this audit and report retention has been addressed. Remove Graph app-role assignments separately after confirming no other workload depends on them.
