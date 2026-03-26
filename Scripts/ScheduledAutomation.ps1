<#
.SYNOPSIS
    Orchestrate scheduled tasks: register, list, remove, run-now.
    Chain multiple scripts into automated workflows.
#>

param(
    [string]$Action,     # Register, List, Remove, RunNow, CreateWorkflow
    [string]$TaskName,
    [string]$ScriptPath,
    [string]$TriggerType = 'Daily',  # Daily, Weekly, AtStartup, AtLogon, Once
    [string]$TriggerTime = '3am',
    [string[]]$WorkflowScripts
)

$ErrorActionPreference = 'Stop'

function Register-AutoTask {
    param([string]$Name, [string]$Script, [string]$Type, [string]$Time)

    $psExe = 'PowerShell.exe'
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
    $taskAction = New-ScheduledTaskAction -Execute $psExe -Argument $psArgs

    $trigger = switch ($Type) {
        'Daily'     { New-ScheduledTaskTrigger -Daily -At $Time }
        'Weekly'    { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time }
        'AtStartup' { New-ScheduledTaskTrigger -AtStartup }
        'AtLogon'   { New-ScheduledTaskTrigger -AtLogon }
        'Once'      { New-ScheduledTaskTrigger -Once -At $Time }
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $Name -Action $taskAction -Trigger $trigger -Settings $settings -Force
    Write-Output "Task '$Name' registered ($Type at $Time)."
}

function Get-AutoTasks {
    Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' } |
        Select-Object TaskName, State, @{N='NextRun';E={(Get-ScheduledTaskInfo $_).NextRunTime}} |
        Format-Table -AutoSize
}

function Remove-AutoTask {
    param([string]$Name)
    Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    Write-Output "Task '$Name' removed."
}

function Start-AutoTask {
    param([string]$Name)
    Start-ScheduledTask -TaskName $Name
    Write-Output "Task '$Name' started."
}

function New-Workflow {
    param([string]$Name, [string[]]$Scripts)

    $workflowDir = Join-Path $PSScriptRoot '..\Workflows'
    if (-not (Test-Path $workflowDir)) { New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null }

    $wfPath = Join-Path $workflowDir "$Name.ps1"
    $content = "# Auto-generated workflow: $Name`n"
    $content += "`$ErrorActionPreference = 'Stop'`n"
    $content += "`$logFile = Join-Path `$PSScriptRoot '..\Logs\workflow_${Name}.log'`n`n"

    foreach ($s in $Scripts) {
        $content += "Write-Output `"[`$(Get-Date -f u)] Running: $s`" | Tee-Object -FilePath `$logFile -Append`n"
        $content += "& '$s'`n`n"
    }

    $content += "Write-Output `"[`$(Get-Date -f u)] Workflow $Name complete.`" | Tee-Object -FilePath `$logFile -Append`n"
    $content | Set-Content -Path $wfPath -Encoding UTF8
    Write-Output "Workflow created: $wfPath"
}

switch ($Action) {
    'Register'       { Register-AutoTask -Name $TaskName -Script $ScriptPath -Type $TriggerType -Time $TriggerTime }
    'List'           { Get-AutoTasks }
    'Remove'         { Remove-AutoTask -Name $TaskName }
    'RunNow'         { Start-AutoTask -Name $TaskName }
    'CreateWorkflow' { New-Workflow -Name $TaskName -Scripts $WorkflowScripts }
    default          { Write-Output 'Actions: Register, List, Remove, RunNow, CreateWorkflow' }
}
