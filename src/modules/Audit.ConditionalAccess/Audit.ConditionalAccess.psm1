Import-Module (Join-Path $PSScriptRoot '..\Audit.Graph\Audit.Graph.psm1') -Force
Export-ModuleMember -Function Get-AuditConditionalAccessPolicies
