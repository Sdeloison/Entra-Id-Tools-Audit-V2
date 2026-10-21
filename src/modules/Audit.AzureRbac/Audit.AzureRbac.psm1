Set-StrictMode -Version Latest

function Get-AuditAzureRbac {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$SubscriptionIds)
    $records = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $successfulSubscriptions = 0
    foreach ($subscriptionId in $SubscriptionIds) {
        try {
            Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
            $assignments = Get-AzRoleAssignment -Scope "/subscriptions/$subscriptionId" -ErrorAction Stop
            $successfulSubscriptions++
            foreach ($assignment in $assignments) {
                $records.Add([pscustomobject]@{
                    id = $assignment.RoleAssignmentId
                    principalId = $assignment.ObjectId
                    principalType = $assignment.ObjectType
                    roleDefinitionName = $assignment.RoleDefinitionName
                    roleDefinitionId = $assignment.RoleDefinitionId
                    assignmentScope = $assignment.Scope
                    queriedSubscriptionId = $subscriptionId
                    inherited = ($assignment.Scope -ne "/subscriptions/$subscriptionId")
                    source = 'Azure Resource Manager'
                    collectedAtUtc = [DateTime]::UtcNow.ToString('o')
                    collectionStatus = 'collected'
                })
            }
            [void]$warnings.Add("Azure RBAC visibility for subscription $subscriptionId depends on the caller's Azure Reader scope; descendant scope coverage may be incomplete.")
        }
        catch {
            [void]$warnings.Add("Azure RBAC collection failed for a configured subscription; see sanitized job diagnostics.")
        }
    }
    $status = if ($successfulSubscriptions -eq 0) { 'failed' } elseif ($warnings.Count -gt 0) { 'partial' } else { 'complete' }
    [pscustomobject]@{ Records = @($records); Status = $status; Warnings = @($warnings) }
}

function Get-AuditManagedIdentityResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$SubscriptionIds,
        [ValidateRange(1, 50000)][int]$MaxResources = 5000
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $successfulSubscriptions = 0
    foreach ($subscriptionId in $SubscriptionIds) {
        try {
            Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
            $perSubscriptionLimit = [Math]::Min(1000, $MaxResources - $records.Count)
            if ($perSubscriptionLimit -le 0) {
                [void]$warnings.Add('Maximum ARM resource count reached; identity inventory is truncated.')
                break
            }
            $resources = Search-AzGraph -Subscription $subscriptionId -First $perSubscriptionLimit -Query "Resources | where isnotempty(identity.type) or type =~ 'Microsoft.ManagedIdentity/userAssignedIdentities' | project id, name, type, subscriptionId, resourceGroup, location, identity, properties" -ErrorAction Stop
            $successfulSubscriptions++
            foreach ($resource in $resources) {
                $identity = $resource.identity
                $isUserAssignedIdentityResource = $resource.type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities'
                $userAssigned = @()
                if ($identity.userAssignedIdentities) {
                    $userAssigned = @($identity.userAssignedIdentities.PSObject.Properties | ForEach-Object {
                        [pscustomobject]@{
                            resourceId = $_.Name
                            clientId = $_.Value.clientId
                            principalId = $_.Value.principalId
                        }
                    })
                }
                $records.Add([pscustomobject]@{
                    id = $resource.id
                    resourceId = $resource.id
                    resourceName = $resource.name
                    resourceType = $resource.type
                    subscriptionId = $resource.subscriptionId
                    resourceGroup = $resource.resourceGroup
                    location = $resource.location
                    identityType = $(if ($isUserAssignedIdentityResource) { 'UserAssignedIdentityResource' } else { $identity.type })
                    principalId = $(if ($isUserAssignedIdentityResource) { $resource.properties.principalId } else { $identity.principalId })
                    clientId = $(if ($isUserAssignedIdentityResource) { $resource.properties.clientId } else { $null })
                    userAssignedIdentities = $userAssigned
                    source = 'Azure Resource Graph'
                    collectedAtUtc = [DateTime]::UtcNow.ToString('o')
                    collectionStatus = 'collected'
                })
            }
            if (@($resources).Count -ge $perSubscriptionLimit) {
                [void]$warnings.Add("Resource Graph result limit may truncate identity resources in subscription $subscriptionId.")
            }
        }
        catch {
            [void]$warnings.Add("Managed identity resource inventory failed for a configured subscription; see sanitized job diagnostics.")
        }
    }
    [void]$warnings.Add('Identity sign-ins, Graph/API grants, role assignments per identity, and observed usage telemetry are not joined by this inventory.')
    $status = if ($successfulSubscriptions -eq 0) { 'failed' } else { 'partial' }
    [pscustomobject]@{ Records = @($records); Status = $status; Warnings = @($warnings) }
}

Export-ModuleMember -Function Get-AuditAzureRbac, Get-AuditManagedIdentityResources
