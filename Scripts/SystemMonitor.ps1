<#
.SYNOPSIS
    Real-time system monitoring: CPU, RAM, Disk, Network, GPU.
    Optional alerts via email or Windows toast notifications.
#>

param(
    [int]$IntervalSec = 5,
    [int]$CpuThreshold = 90,
    [int]$RamThreshold = 90,
    [int]$DiskThreshold = 90,
    [switch]$LogToFile,
    [switch]$Toast,
    [string]$SmtpServer,
    [string]$AlertEmail
)

$logRoot = Join-Path $PSScriptRoot '..\Logs'
if (-not (Test-Path $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logFile = Join-Path $logRoot ("SystemMonitor_{0:yyyyMMdd}.log" -f (Get-Date))

function Get-SystemInfo {
    $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 1)
    $os  = Get-CimInstance Win32_OperatingSystem
    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $ramFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramUsed  = $ramTotal - $ramFree
    $ramPct   = [math]::Round(($ramUsed / $ramTotal) * 100, 1)

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [PSCustomObject]@{
            Drive    = $_.DeviceID
            SizeGB   = [math]::Round($_.Size / 1GB, 1)
            FreeGB   = [math]::Round($_.FreeSpace / 1GB, 1)
            UsedPct  = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
        }
    }

    $net = Get-NetAdapterStatistics -ErrorAction SilentlyContinue | Select-Object Name,
        @{N='SentMB';E={[math]::Round($_.SentBytes/1MB,1)}},
        @{N='RecvMB';E={[math]::Round($_.ReceivedBytes/1MB,1)}}

    [PSCustomObject]@{
        Timestamp = Get-Date -Format 'u'
        CPU_Pct   = $cpu
        RAM_Pct   = $ramPct
        RAM_Used  = "${ramUsed}GB / ${ramTotal}GB"
        Disks     = $disks
        Network   = $net
    }
}

function Send-Alert {
    param([string]$Message)
    if ($Toast) {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Warning
        $notify.Visible = $true
        $notify.ShowBalloonTip(5000, 'System Alert', $Message, 'Warning')
        Start-Sleep -Seconds 6
        $notify.Dispose()
    }
    if ($SmtpServer -and $AlertEmail) {
        Send-MailMessage -From 'monitor@localhost' -To $AlertEmail -Subject 'System Alert' -Body $Message -SmtpServer $SmtpServer
    }
    Write-Warning "ALERT: $Message"
}

Write-Host "SystemMonitor started (interval: ${IntervalSec}s). Ctrl+C to stop." -ForegroundColor Green

while ($true) {
    $info = Get-SystemInfo

    $line = "$($info.Timestamp) | CPU: $($info.CPU_Pct)% | RAM: $($info.RAM_Pct)% ($($info.RAM_Used))"
    $info.Disks | ForEach-Object { $line += " | $($_.Drive) $($_.UsedPct)%" }
    Write-Host $line

    if ($LogToFile) { $line | Out-File -FilePath $logFile -Append }

    if ($info.CPU_Pct -ge $CpuThreshold) { Send-Alert "CPU at $($info.CPU_Pct)%" }
    if ($info.RAM_Pct -ge $RamThreshold) { Send-Alert "RAM at $($info.RAM_Pct)%" }
    $info.Disks | Where-Object { $_.UsedPct -ge $DiskThreshold } | ForEach-Object {
        Send-Alert "Disk $($_.Drive) at $($_.UsedPct)%"
    }

    Start-Sleep -Seconds $IntervalSec
}
