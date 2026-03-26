param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [switch]$EnableRemoting,
    [switch]$CheckSpooler,
    [switch]$RegisterBackupTask
)

$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $PSScriptRoot '..\Logs'
if (-not (Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}
$logFile = Join-Path $logRoot ("ServerAdmin_{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Message
    $line | Tee-Object -FilePath $logFile -Append
}

try {
    Write-Log "Start ServerAdmin for: $($ComputerName -join ', ')"

    if ($EnableRemoting) {
        Write-Log "Enable-PSRemoting on target servers..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Enable-PSRemoting -Force
        }
        Write-Log "Enable-PSRemoting finished."
    }

    if ($CheckSpooler) {
        Write-Log "Check and restart Spooler if needed..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $svc = Get-Service -Name 'Spooler'
            if ($svc.Status -ne 'Running') {
                Restart-Service -Name 'Spooler' -Force
                "$env:COMPUTERNAME: Spooler restarted."
            } else {
                "$env:COMPUTERNAME: Spooler is running."
            }
        } | ForEach-Object { Write-Log $_ }
    }

    if ($RegisterBackupTask) {
        Write-Log "Register backup task on targets..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $action  = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\backup.ps1'
            $trigger = New-ScheduledTaskTrigger -Daily -At 2am
            Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'DailyBackup' -Force
        }
        Write-Log "Backup tasks registered."
    }

    Write-Log "ServerAdmin finished successfully."
}
catch {
    Write-Log "ERROR: $_" 'ERROR'
    throw
}
