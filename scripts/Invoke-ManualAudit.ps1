[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AutomationAccountName,
    [Parameter(Mandatory)][string]$RunbookName,
    [Parameter(Mandatory)][hashtable]$Parameters
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Automation -ErrorAction Stop
Connect-AzAccount -ErrorAction Stop | Out-Null
$confirmation = Read-Host "Start runbook '$RunbookName' in '$AutomationAccountName'? Type RUN"
if ($confirmation -cne 'RUN') { throw 'Run cancelled.' }
$job = Start-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $RunbookName -Parameters $Parameters -ErrorAction Stop
Write-Output ([pscustomobject]@{ jobId = $job.JobId; status = $job.Status; runbook = $RunbookName })
