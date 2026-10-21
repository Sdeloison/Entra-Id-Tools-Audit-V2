Set-StrictMode -Version Latest

function Get-AuditUtcNow {
    [CmdletBinding()]
    param()
    [DateTime]::UtcNow.ToString('o')
}

function New-AuditSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Collector,
        [Parameter(Mandatory)][string]$Name,
        [string]$WindowStartUtc,
        [string]$WindowEndUtc
    )

    $collectedAt = Get-AuditUtcNow
    try {
        $result = & $Collector
        $records = @($result.Records)
        $warnings = @($result.Warnings)
        $status = if ($result.Status) { [string]$result.Status } else { 'complete' }
        [pscustomobject]@{
            status = $status
            collectedAtUtc = $collectedAt
            windowStartUtc = $WindowStartUtc
            windowEndUtc = $WindowEndUtc
            recordCount = $records.Count
            warnings = $warnings
            errors = @()
            records = $records
        }
    }
    catch {
        $httpStatus = $null
        try { $httpStatus = [int]$_.Exception.Response.StatusCode } catch { }
        $errorCode = if ($httpStatus) { "HTTP_$httpStatus" } else { $_.Exception.GetType().Name }
        [pscustomobject]@{
            status = 'failed'
            collectedAtUtc = $collectedAt
            windowStartUtc = $WindowStartUtc
            windowEndUtc = $WindowEndUtc
            recordCount = 0
            warnings = @()
            errors = @([pscustomobject]@{ code = $errorCode; message = 'Collection failed; see sanitized job diagnostics.' })
            records = @()
        }
    }
}

function Invoke-AuditGraphPagedQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateRange(1, 50000)][int]$MaxRecords = 5000
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    $truncated = $false
    while ($nextUri -and $items.Count -lt $MaxRecords) {
        $response = $null
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            try {
                $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri -OutputType PSObject -ErrorAction Stop
                break
            }
            catch {
                $status = 0
                try { $status = [int]$_.Exception.Response.StatusCode } catch { }
                if ($attempt -ge 3 -or ($status -notin @(429, 500, 502, 503, 504))) { throw }
                $delay = [Math]::Min(30, [Math]::Pow(2, $attempt + 1))
                try {
                    $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
                    if ($retryAfter -gt 0) { $delay = [Math]::Min(60, $retryAfter) }
                } catch { }
                Start-Sleep -Seconds ([int][Math]::Ceiling($delay))
            }
        }
        foreach ($item in @($response.value)) {
            if ($items.Count -ge $MaxRecords) { $truncated = $true; break }
            $items.Add($item)
        }
        if ($items.Count -ge $MaxRecords) {
            $truncated = [bool]$response.'@odata.nextLink'
            break
        }
        $nextUri = $response.'@odata.nextLink'
    }
    [pscustomobject]@{ Records = @($items); Truncated = $truncated }
}

function New-AuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$CollectedAtUtc,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    $record = [ordered]@{ id = $Id }
    foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
    $record.source = $Source
    $record.collectedAtUtc = $CollectedAtUtc
    $record.collectionStatus = 'collected'
    [pscustomobject]$record
}

Export-ModuleMember -Function Get-AuditUtcNow, New-AuditSection, Invoke-AuditGraphPagedQuery, New-AuditRecord
