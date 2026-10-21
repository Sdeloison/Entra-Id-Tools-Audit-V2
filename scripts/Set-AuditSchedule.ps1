[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AutomationAccountName,
    [Parameter(Mandatory)][string]$RunbookName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScheduleName,
    [Parameter(Mandatory)][datetime]$StartTime,
    [ValidateRange(1, 365)][int]$DayInterval = 1,
    [Parameter(Mandatory)][string]$TimeZone,
    [Parameter(Mandatory)][hashtable]$Parameters,
    [switch]$Enable
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Enable) {
    Write-Output ([pscustomobject]@{ action = 'preview only'; scheduleName = $ScheduleName; startTime = $StartTime; dayInterval = $DayInterval; timeZone = $TimeZone })
    return
}
$confirmation = Read-Host "Create and enable schedule '$ScheduleName' for '$RunbookName'? Type ENABLE"
if ($confirmation -cne 'ENABLE') { throw 'Schedule activation cancelled.' }
Import-Module Az.Automation -ErrorAction Stop
if ($PSCmdlet.ShouldProcess("$AutomationAccountName/$ScheduleName", 'Create schedule and link runbook')) {
    $schedule = New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ScheduleName -StartTime $StartTime -DayInterval $DayInterval -TimeZone $TimeZone -ErrorAction Stop
    Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $RunbookName -ScheduleName $ScheduleName -Parameters $Parameters -ErrorAction Stop | Out-Null
    Write-Output ([pscustomobject]@{ scheduleName = $schedule.Name; runbookName = $RunbookName; status = 'enabled' })
}
