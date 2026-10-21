param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TenantId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$StorageAccountName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ReportContainer,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$SubscriptionIds,
    [ValidateRange(1, 365)][int]$LookbackDays = 30,
    [ValidateRange(1, 50000)][int]$MaxGraphRecords = 5000,
    [ValidateRange(0, 10000)][int]$MaxGroupsForMemberships = 500,
    [ValidateRange(1, 50000)][int]$MaxArmResources = 5000,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UserAssignedIdentityClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\Audit.Common\Audit.Common.psm1') -Force
Import-Module (Join-Path $root 'modules\Audit.Graph\Audit.Graph.psm1') -Force
Import-Module (Join-Path $root 'modules\Audit.AzureRbac\Audit.AzureRbac.psm1') -Force
Import-Module Az.ResourceGraph -ErrorAction Stop
Import-Module (Join-Path $root 'modules\Audit.EntitlementManagement\Audit.EntitlementManagement.psm1') -Force
Import-Module (Join-Path $root 'modules\Audit.FinanceOperations\Audit.FinanceOperations.psm1') -Force

$startedAt = [DateTime]::UtcNow
$windowStart = $startedAt.AddDays(-$LookbackDays)
$windowEnd = $startedAt
$connectArgs = @{ Identity = $true; AccountId = $UserAssignedIdentityClientId; ErrorAction = 'Stop' }
$azConnected = $false
$graphConnected = $false
$azConnectionError = $null
$graphConnectionError = $null
try {
    Connect-AzAccount @connectArgs | Out-Null
    $azConnected = $true
}
catch {
    $azConnectionError = $_.Exception.GetType().Name
}
try {
    Connect-MgGraph -Identity -ClientId $UserAssignedIdentityClientId -TenantId $TenantId -NoWelcome -ErrorAction Stop
    $graphConnected = $true
}
catch {
    $graphConnectionError = $_.Exception.GetType().Name
}

$sections = [ordered]@{}
$sections.users = New-AuditSection -Name 'users' -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditUsers -MaxRecords $MaxGraphRecords
}
$sections.groups = New-AuditSection -Name 'groups' -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditGroups -MaxRecords $MaxGraphRecords -MaxGroupsForMemberships $MaxGroupsForMemberships
}
$sections.signInLogs = New-AuditSection -Name 'signInLogs' -WindowStartUtc $windowStart.ToString('o') -WindowEndUtc $windowEnd.ToString('o') -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditSignInLogs -WindowStartUtc $windowStart -WindowEndUtc $windowEnd -MaxRecords ([Math]::Min($MaxGraphRecords, 5000))
}
$sections.conditionalAccessPolicies = New-AuditSection -Name 'conditionalAccessPolicies' -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditConditionalAccessPolicies -MaxRecords $MaxGraphRecords
}
$sections.servicePrincipals = New-AuditSection -Name 'servicePrincipals' -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditServicePrincipals -MaxRecords $MaxGraphRecords
}
$sections.applications = New-AuditSection -Name 'applications' -Collector {
    if (-not $graphConnected) { throw 'Microsoft Graph managed identity connection failed.' }
    Get-AuditApplications -MaxRecords $MaxGraphRecords
}
$sections.azureRbac = New-AuditSection -Name 'azureRbac' -Collector {
    if (-not $azConnected) { throw 'Azure managed identity connection failed.' }
    Get-AuditAzureRbac -SubscriptionIds $SubscriptionIds
}
$sections.managedIdentityResources = New-AuditSection -Name 'managedIdentityResources' -Collector {
    if (-not $azConnected) { throw 'Azure managed identity connection failed.' }
    Get-AuditManagedIdentityResources -SubscriptionIds $SubscriptionIds -MaxResources $MaxArmResources
}
$sections.entitlementManagement = New-AuditSection -Name 'entitlementManagement' -Collector { Get-AuditEntitlementManagement }
$sections.financeOperations = New-AuditSection -Name 'financeOperations' -Collector { Get-AuditFinanceOperations }
$notCollected = {
    param([string]$Message)
    [pscustomobject]@{ Records = @(); Status = 'not_configured'; Warnings = @($Message) }
}
$sections.directoryRoleAssignments = New-AuditSection -Name 'directoryRoleAssignments' -Collector { & $notCollected 'Active and eligible Entra role assignments are not collected by this version.' }
$sections.microsoft365Roles = New-AuditSection -Name 'microsoft365Roles' -Collector { & $notCollected 'Microsoft 365 role assignments are not collected by this version.' }

$report = [ordered]@{
    schemaVersion = '1.0'
    runId = [guid]::NewGuid().ToString()
    tenantId = $TenantId
    startedAtUtc = $startedAt.ToString('o')
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    windowStartUtc = $windowStart.ToString('o')
    windowEndUtc = $windowEnd.ToString('o')
    configuredSubscriptionIds = @($SubscriptionIds)
    connections = [ordered]@{
        graph = [ordered]@{ status = $(if ($graphConnected) { 'connected' } else { 'failed' }); errorType = $graphConnectionError }
        azure = [ordered]@{ status = $(if ($azConnected) { 'connected' } else { 'failed' }); errorType = $azConnectionError }
    }
    sections = $sections
}
$json = $report | ConvertTo-Json -Depth 40
$fileName = "$($startedAt.ToString('yyyyMMddTHHmmssZ'))-$($report.runId).json"
$tempPath = Join-Path ([IO.Path]::GetTempPath()) $fileName
$latestPath = Join-Path ([IO.Path]::GetTempPath()) "latest-$($report.runId).json"
try {
    Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8NoBOM
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    $blobPath = "runs/$($startedAt.ToString('yyyy/MM/dd'))/$fileName"
    Set-AzStorageBlobContent -File $tempPath -Container $ReportContainer -Blob $blobPath -Context $context -Force -ErrorAction Stop | Out-Null
    [ordered]@{ blobName = $blobPath; runId = $report.runId; completedAtUtc = $report.completedAtUtc } |
        ConvertTo-Json | Set-Content -LiteralPath $latestPath -Encoding utf8NoBOM
    Set-AzStorageBlobContent -File $latestPath -Container $ReportContainer -Blob 'latest.json' -Context $context -Force -ErrorAction Stop | Out-Null
    Write-Output ([pscustomobject]@{ status = 'published'; blob = $blobPath; runId = $report.runId; completedAtUtc = $report.completedAtUtc })
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $latestPath -Force -ErrorAction SilentlyContinue
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
