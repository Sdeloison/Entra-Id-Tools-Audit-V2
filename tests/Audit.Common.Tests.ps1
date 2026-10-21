Import-Module (Join-Path $PSScriptRoot '..\src\modules\Audit.Common\Audit.Common.psm1') -Force

Describe 'Audit common result semantics' {
    It 'returns collected records and a complete status' {
        $result = New-AuditSection -Name users -Collector {
            [pscustomobject]@{ Records = @([pscustomobject]@{ id = 'synthetic' }); Status = 'complete'; Warnings = @() }
        }
        if ($result.status -ne 'complete') { throw 'Expected complete status.' }
        if ($result.recordCount -ne 1) { throw 'Expected one record.' }
        if ($result.records[0].id -ne 'synthetic') { throw 'Expected the synthetic record ID.' }
    }

    It 'surfaces failure without exposing exception text or pretending success' {
        $result = New-AuditSection -Name users -Collector { throw 'secret token example' }
        if ($result.status -ne 'failed') { throw 'Expected failed status.' }
        if ($result.recordCount -ne 0) { throw 'Expected zero records after failure.' }
        if (($result | ConvertTo-Json -Depth 5) -match 'secret token example') { throw 'Exception details were not sanitized.' }
    }

    It 'preserves explicit not_configured coverage' {
        $result = New-AuditSection -Name financeOperations -Collector {
            [pscustomobject]@{ Records = @(); Status = 'not_configured'; Warnings = @('No connector') }
        }
        if ($result.status -ne 'not_configured') { throw 'Expected not_configured status.' }
        if ($result.warnings.Count -ne 1) { throw 'Expected explicit coverage warning.' }
    }
}
