[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$ExpectedTagValue
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate resource group; nothing was deleted.' }
if (-not $resources -or @($resources).Count -eq 0) { throw 'Resource group is empty or unavailable; refusing deletion.' }
$ownedRootTypes = @(
    'Microsoft.ManagedIdentity/userAssignedIdentities',
    'Microsoft.Automation/automationAccounts',
    'Microsoft.Storage/storageAccounts',
    'Microsoft.Web/serverfarms',
    'Microsoft.Web/sites'
)
$rootResources = @($resources | Where-Object { $_.type -in $ownedRootTypes })
$missingRoots = @($ownedRootTypes | Where-Object { $_ -notin @($rootResources | ForEach-Object { $_.type }) })
$otherRootResources = @($resources | Where-Object {
    ($_.type -split '/').Count -eq 2 -and
    $_.type -notin @('Microsoft.Authorization/roleAssignments', 'Microsoft.Resources/deployments') -and
    $_.type -notin $ownedRootTypes
})
if ($missingRoots.Count -gt 0) { throw 'Expected audit resources are missing; refusing resource-group deletion.' }
if ($otherRootResources.Count -gt 0) { throw 'Resource group contains an unexpected top-level resource; refusing deletion.' }
$untagged = @($rootResources | Where-Object { $_.tags.EntraTenantAudit -ne $ExpectedTagValue })
if ($untagged.Count -gt 0) {
    throw 'At least one audit resource does not have the expected ownership tag; refusing resource-group deletion.'
}
$rootResources | Select-Object name,type,id | Format-Table -AutoSize
if ($PSCmdlet.ShouldProcess("Resource group $ResourceGroupName", 'Delete all tagged resources and report data')) {
    $confirmation = Read-Host "Verify report retention and type DELETE $ResourceGroupName"
    if ($confirmation -cne "DELETE $ResourceGroupName") { throw 'Deletion cancelled.' }
    az group delete --name $ResourceGroupName --yes
    if ($LASTEXITCODE -ne 0) { throw 'Azure resource group deletion failed.' }
}
