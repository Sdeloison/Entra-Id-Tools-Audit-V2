Import-Module (Join-Path $PSScriptRoot '..\Audit.AzureRbac\Audit.AzureRbac.psm1') -Force
Export-ModuleMember -Function Get-AuditManagedIdentityResources
