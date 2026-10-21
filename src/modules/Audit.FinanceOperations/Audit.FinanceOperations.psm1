function Get-AuditFinanceOperations {
    [CmdletBinding()]
    param([bool]$Configured = $false)
    if (-not $Configured) {
        return [pscustomobject]@{
            Records = @()
            Status = 'not_configured'
            Warnings = @('A supported Dynamics 365 Finance & Operations integration has not been configured.')
        }
    }
    [pscustomobject]@{
        Records = @()
        Status = 'not_configured'
        Warnings = @('F&O integration is marked configured but no supported connector implementation is present; no F&O role data was collected.')
    }
}
Export-ModuleMember -Function Get-AuditFinanceOperations
