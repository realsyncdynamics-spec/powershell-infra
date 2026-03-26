<#
.SYNOPSIS
    Watch folders for changes and auto-react: copy, move, log, execute scripts.
#>

param(
    [string]$WatchPath = 'C:\Data',
    [string]$Filter = '*.*',
    [switch]$IncludeSubdirs,
    [string]$ActionScript,
    [string]$MoveToPath,
    [string]$CopyToPath
)

$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $PSScriptRoot '..\Logs'
if (-not (Test-Path $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logFile = Join-Path $logRoot ("FileWatcher_{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0:u} {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $logFile -Append
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchPath
$watcher.Filter = $Filter
$watcher.IncludeSubdirectories = [bool]$IncludeSubdirs
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor
                         [System.IO.NotifyFilters]::LastWrite -bor
                         [System.IO.NotifyFilters]::DirectoryName

$action = {
    $path = $Event.SourceEventArgs.FullPath
    $change = $Event.SourceEventArgs.ChangeType
    $time = (Get-Date -Format 'u')
    Write-Host "[$time] $change : $path"
    "$time $change $path" | Out-File -FilePath $using:logFile -Append

    if ($using:CopyToPath -and (Test-Path $path)) {
        Copy-Item -Path $path -Destination $using:CopyToPath -Force
    }
    if ($using:MoveToPath -and (Test-Path $path) -and $change -eq 'Created') {
        Move-Item -Path $path -Destination $using:MoveToPath -Force
    }
    if ($using:ActionScript -and (Test-Path $using:ActionScript)) {
        & $using:ActionScript -FilePath $path -ChangeType $change
    }
}

Register-ObjectEvent $watcher 'Created' -Action $action | Out-Null
Register-ObjectEvent $watcher 'Changed' -Action $action | Out-Null
Register-ObjectEvent $watcher 'Deleted' -Action $action | Out-Null
Register-ObjectEvent $watcher 'Renamed' -Action $action | Out-Null

Write-Log "Watching: $WatchPath (Filter: $Filter, Subdirs: $IncludeSubdirs)"
Write-Host "FileSystemWatcher active. Press Ctrl+C to stop." -ForegroundColor Green

try { while ($true) { Start-Sleep -Seconds 1 } }
finally {
    Get-EventSubscriber | Unregister-Event
    $watcher.Dispose()
    Write-Log "Watcher stopped."
}
