Set-StrictMode -Version Latest

function Get-AuditUsers {
    [CmdletBinding()]
    param([ValidateRange(1, 50000)][int]$MaxRecords = 5000)
    $query = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime&`$top=999" -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = foreach ($user in $query.Records) {
        New-AuditRecord -Id $user.id -Source 'Microsoft Graph v1.0' -CollectedAtUtc $now -Fields @{
            displayName = $user.displayName
            userPrincipalName = $user.userPrincipalName
            userType = $user.userType
            accountEnabled = $user.accountEnabled
            createdDateTime = $user.createdDateTime
            isGuest = ($user.userType -eq 'Guest')
        }
    }
    [pscustomobject]@{ Records = @($rows); Status = $(if ($query.Truncated) { 'partial' } else { 'complete' }); Warnings = $(if ($query.Truncated) { @('Maximum user record count reached; inventory is truncated.') } else { @() }) }
}

function Get-AuditGroups {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 50000)][int]$MaxRecords = 5000,
        [ValidateRange(0, 10000)][int]$MaxGroupsForMemberships = 500
    )
    $query = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/groups?`$select=id,displayName,description,createdDateTime,groupTypes,mailEnabled,securityEnabled,visibility,membershipRule&`$top=999" -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($group in $query.Records) {
        $index++
        $memberIds = @()
        $memberStatus = 'not_collected'
        if ($index -le $MaxGroupsForMemberships) {
            try {
                $members = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members?`$select=id&`$top=999" -MaxRecords 500
                $memberIds = @($members.Records | ForEach-Object { $_.id })
                $memberStatus = if ($members.Truncated) { 'partial' } else { 'complete' }
                if ($members.Truncated) {
                    [void]$warnings.Add('A group membership result reached its per-group cap.')
                }
            }
            catch {
                $memberStatus = 'failed'
                [void]$warnings.Add("Member collection failed for a group; see sanitized job diagnostics.")
            }
        }
        $rows.Add((New-AuditRecord -Id $group.id -Source 'Microsoft Graph v1.0' -CollectedAtUtc $now -Fields @{
            displayName = $group.displayName
            description = $group.description
            createdDateTime = $group.createdDateTime
            groupTypes = @($group.groupTypes)
            mailEnabled = $group.mailEnabled
            securityEnabled = $group.securityEnabled
            visibility = $group.visibility
            membershipType = $(if ($group.groupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' })
            directMemberIds = $memberIds
            directMembersStatus = $memberStatus
        }))
    }
    if ($query.Truncated) { [void]$warnings.Add('Maximum group record count reached; inventory is truncated.') }
    if ($query.Records.Count -gt $MaxGroupsForMemberships) { [void]$warnings.Add('Membership collection was capped; no nested/transitive memberships or owners were collected.') }
    [pscustomobject]@{ Records = @($rows); Status = $(if ($warnings.Count -gt 0) { 'partial' } else { 'complete' }); Warnings = @($warnings) }
}

function Get-AuditConditionalAccessPolicies {
    [CmdletBinding()]
    param([ValidateRange(1, 50000)][int]$MaxRecords = 5000)
    $query = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$top=999" -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = foreach ($policy in $query.Records) {
        New-AuditRecord -Id $policy.id -Source 'Microsoft Graph v1.0' -CollectedAtUtc $now -Fields @{
            displayName = $policy.displayName
            state = $policy.state
            conditions = $policy.conditions
            grantControls = $policy.grantControls
            sessionControls = $policy.sessionControls
            createdDateTime = $policy.createdDateTime
            modifiedDateTime = $policy.modifiedDateTime
            effectiveEnforcementObserved = $false
        }
    }
    $warning = @('Policy targeting is collected; this is not effective per-user evaluation. Applied sign-in results are not joined.')
    if ($query.Truncated) { $warning += 'Maximum policy record count reached; inventory is truncated.' }
    [pscustomobject]@{ Records = @($rows); Status = 'partial'; Warnings = $warning }
}

function Get-AuditServicePrincipals {
    [CmdletBinding()]
    param([ValidateRange(1, 50000)][int]$MaxRecords = 5000)
    $query = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId,createdDateTime,publisherName,verifiedPublisher,tags&`$top=999" -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = foreach ($item in $query.Records) {
        New-AuditRecord -Id $item.id -Source 'Microsoft Graph v1.0' -CollectedAtUtc $now -Fields @{
            appId = $item.appId
            displayName = $item.displayName
            servicePrincipalType = $item.servicePrincipalType
            accountEnabled = $item.accountEnabled
            homeTenantId = $item.appOwnerOrganizationId
            createdDateTime = $item.createdDateTime
            publisherName = $item.publisherName
            verifiedPublisher = $item.verifiedPublisher
            tags = @($item.tags)
        }
    }
    $warnings = @('Role grants, delegated grants, owners, credentials, sign-in telemetry, and Conditional Access workload enforcement are not collected.')
    if ($query.Truncated) { $warnings += 'Maximum service principal record count reached; inventory is truncated.' }
    [pscustomobject]@{ Records = @($rows); Status = 'partial'; Warnings = $warnings }
}

function Get-AuditApplications {
    [CmdletBinding()]
    param([ValidateRange(1, 50000)][int]$MaxRecords = 5000)
    $query = Invoke-AuditGraphPagedQuery -Uri "https://graph.microsoft.com/v1.0/applications?`$select=id,appId,displayName,createdDateTime,signInAudience,publisherDomain,verifiedPublisher,tags,requiredResourceAccess,appRoles,oauth2PermissionScopes&`$top=999" -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = foreach ($item in $query.Records) {
        New-AuditRecord -Id $item.id -Source 'Microsoft Graph v1.0' -CollectedAtUtc $now -Fields @{
            appId = $item.appId
            displayName = $item.displayName
            createdDateTime = $item.createdDateTime
            signInAudience = $item.signInAudience
            publisherDomain = $item.publisherDomain
            verifiedPublisher = $item.verifiedPublisher
            tags = @($item.tags)
            requiredResourceAccess = $item.requiredResourceAccess
            appRoles = $item.appRoles
            oauth2PermissionScopes = $item.oauth2PermissionScopes
            requestedPermissionsAreNotConsent = $true
        }
    }
    $warnings = @('Configured API permissions are requested permissions, not proof of consent. Actual grants, owners, credentials, and usage are not collected.')
    if ($query.Truncated) { $warnings += 'Maximum application record count reached; inventory is truncated.' }
    [pscustomobject]@{ Records = @($rows); Status = 'partial'; Warnings = $warnings }
}

function Get-AuditSignInLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$WindowStartUtc,
        [Parameter(Mandatory)][datetime]$WindowEndUtc,
        [ValidateRange(1, 50000)][int]$MaxRecords = 1000
    )
    $start = $WindowStartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $filter = [uri]::EscapeDataString("createdDateTime ge $start and status/errorCode eq 0")
    $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$select=id,userId,userPrincipalName,createdDateTime,appDisplayName,resourceDisplayName,signInEventTypes&`$top=100"
    $query = Invoke-AuditGraphPagedQuery -Uri $uri -MaxRecords $MaxRecords
    $now = Get-AuditUtcNow
    $rows = foreach ($item in $query.Records) {
        New-AuditRecord -Id $item.id -Source 'Microsoft Graph v1.0 sign-in logs' -CollectedAtUtc $now -Fields @{
            userId = $item.userId
            userPrincipalName = $item.userPrincipalName
            createdDateTime = $item.createdDateTime
            appDisplayName = $item.appDisplayName
            resourceDisplayName = $item.resourceDisplayName
            signInEventTypes = @($item.signInEventTypes)
            result = 'success'
        }
    }
    [pscustomobject]@{ Records = @($rows); Status = $(if ($query.Truncated) { 'partial' } else { 'complete' }); Warnings = $(if ($query.Truncated) { @('Sign-in log record cap reached; results are truncated.') } else { @('Logs are limited by tenant licensing, permissions, and retention; absence is not evidence of non-use.') }) }
}

Export-ModuleMember -Function Get-AuditUsers, Get-AuditGroups, Get-AuditConditionalAccessPolicies, Get-AuditServicePrincipals, Get-AuditApplications, Get-AuditSignInLogs
