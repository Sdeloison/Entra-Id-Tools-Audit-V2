[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AutomationAccountName,
    [string]$RunbookName = 'Invoke-EntraTenantAudit',
    [switch]$Publish
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Az.Automation -ErrorAction Stop
$path = Join-Path $PSScriptRoot '..\src\runbooks\Invoke-EntraTenantAudit.ps1'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Runbook source not found: $path" }
$modulePaths = @(
    (Join-Path $PSScriptRoot '..\src\modules\Audit.Common\Audit.Common.psm1'),
    (Join-Path $PSScriptRoot '..\src\modules\Audit.Graph\Audit.Graph.psm1'),
    (Join-Path $PSScriptRoot '..\src\modules\Audit.AzureRbac\Audit.AzureRbac.psm1'),
    (Join-Path $PSScriptRoot '..\src\modules\Audit.EntitlementManagement\Audit.EntitlementManagement.psm1'),
    (Join-Path $PSScriptRoot '..\src\modules\Audit.FinanceOperations\Audit.FinanceOperations.psm1')
)
foreach ($modulePath in $modulePaths) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Required collector module not found: $modulePath" }
}
if ($Publish) {
    $confirmation = Read-Host "Publish the imported draft '$RunbookName' in '$AutomationAccountName'? Type PUBLISH"
    if ($confirmation -cne 'PUBLISH') { throw 'Runbook publication cancelled.' }
    if ($PSCmdlet.ShouldProcess("$AutomationAccountName/$RunbookName", 'Publish imported runbook')) {
        Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $RunbookName -ErrorAction Stop | Out-Null
    }
    return
}
if ($PSCmdlet.ShouldProcess("$AutomationAccountName/$RunbookName", 'Import collector and runbook source')) {
    $tempPath = Join-Path ([IO.Path]::GetTempPath()) "$RunbookName-$([guid]::NewGuid().ToString('N')).ps1"
    try {
        $source = [System.Collections.Generic.List[string]]::new()
        foreach ($modulePath in $modulePaths) {
            $moduleContent = Get-Content -LiteralPath $modulePath -Raw
            $moduleContent = [regex]::Replace($moduleContent, '(?m)^\s*Export-ModuleMember\b.*(?:\r?\n|$)', '')
            $source.Add($moduleContent)
        }
        $runbookContent = Get-Content -LiteralPath $path -Raw
        $runbookTokens = $null
        $runbookErrors = $null
        $runbookAst = [System.Management.Automation.Language.Parser]::ParseInput($runbookContent, [ref]$runbookTokens, [ref]$runbookErrors)
        if ($runbookErrors.Count -gt 0 -or -not $runbookAst.ParamBlock) { throw 'Runbook source is invalid or has no parameter block.' }
        $paramBlock = $runbookAst.ParamBlock.Extent
        $paramText = $paramBlock.Text
        $runbookContent = $runbookContent.Remove($paramBlock.StartOffset, $paramBlock.EndOffset - $paramBlock.StartOffset)
        $runbookContent = [regex]::Replace($runbookContent, '(?m)^\$root = Split-Path -Parent \$PSScriptRoot\r?\n', '')
        $runbookContent = [regex]::Replace($runbookContent, '(?m)^Import-Module \(Join-Path \$root .+Audit\.(?:Common|Graph|AzureRbac|EntitlementManagement|FinanceOperations).+?\r?\n', '')
        $source.Insert(0, $paramText)
        $source.Add($runbookContent)
        Set-Content -LiteralPath $tempPath -Value ($source -join "`r`n") -Encoding utf8
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($tempPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) { throw "Generated runbook failed PowerShell syntax validation: $($parseErrors[0].Message)" }
        Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $RunbookName -Type PowerShell -Path $tempPath -Force -ErrorAction Stop | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}
