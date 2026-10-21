[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ResourceGroupName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Location,
    [switch]$WhatIf,
    [switch]$Deploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (($WhatIf.IsPresent -and $Deploy.IsPresent) -or (-not $WhatIf.IsPresent -and -not $Deploy.IsPresent)) {
    throw 'Specify exactly one of -WhatIf or -Deploy.'
}
$template = Join-Path $PSScriptRoot '..\infra\main.bicep'
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Unable to select Azure subscription.' }
az bicep build --file $template --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep build validation failed.' }
if ($WhatIf) {
    az deployment group what-if --resource-group $ResourceGroupName --template-file $template --parameters location=$Location
}
else {
    $confirmation = Read-Host "Deploy EntraTenantAudit resources to '$ResourceGroupName' in '$Location'? Type DEPLOY"
    if ($confirmation -cne 'DEPLOY') { throw 'Deployment cancelled.' }
    az deployment group create --resource-group $ResourceGroupName --template-file $template --parameters location=$Location
}
if ($LASTEXITCODE -ne 0) { throw 'Azure deployment command failed.' }
