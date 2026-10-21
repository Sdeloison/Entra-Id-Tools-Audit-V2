[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ManagedIdentityPrincipalId,
    [string[]]$Permission = @('User.Read.All', 'Group.Read.All', 'GroupMember.Read.All', 'Policy.Read.All', 'Application.Read.All', 'AuditLog.Read.All'),
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$forbidden = @('Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All')
if ($Permission | Where-Object { $_ -in $forbidden }) { throw 'Write-capable or disallowed permissions are not permitted by this bootstrap script.' }
if (-not $Apply) {
    Write-Output ([pscustomobject]@{ tenantId = $TenantId; managedIdentityPrincipalId = $ManagedIdentityPrincipalId; requestedPermissions = $Permission; action = 'preview only; no Graph grants made' })
    return
}
$confirmation = Read-Host "Grant the listed Microsoft Graph application permissions to '$ManagedIdentityPrincipalId' in tenant '$TenantId'? Type GRANT"
if ($confirmation -cne 'GRANT') { throw 'Permission assignment cancelled.' }
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Connect-MgGraph -TenantId $TenantId -Scopes 'AppRoleAssignment.ReadWrite.All','Application.Read.All' -NoWelcome -ErrorAction Stop
try {
    $graphResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId%20eq%20'00000003-0000-0000-c000-000000000000'&`$select=id,appRoles" -ErrorAction Stop
    $graph = @($graphResponse.value)[0]
    if (-not $graph) { throw 'Microsoft Graph service principal was not found.' }
    $identity = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ManagedIdentityPrincipalId?`$select=id" -ErrorAction Stop
    if (-not $identity.id) { throw 'Managed identity service principal was not found.' }
    foreach ($name in $Permission) {
        $appRole = $graph.appRoles | Where-Object { $_.value -eq $name -and $_.allowedMemberTypes -contains 'Application' }
        if (-not $appRole) { throw "Required Graph application permission '$name' was not found." }
        $existingResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($identity.id)/appRoleAssignments?`$filter=resourceId%20eq%20$($graph.id)" -ErrorAction Stop
        $existing = @($existingResponse.value | Where-Object { $_.resourceId -eq $graph.id -and $_.appRoleId -eq $appRole.id })
        if ($existing) { continue }
        if ($PSCmdlet.ShouldProcess("$($identity.id) -> Microsoft Graph/$name", 'Assign application permission')) {
            $body = @{
                principalId = $identity.id
                resourceId = $graph.id
                appRoleId = $appRole.id
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($identity.id)/appRoleAssignments" -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
        }
    }
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
