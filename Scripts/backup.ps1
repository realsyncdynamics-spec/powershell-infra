param(
    [string]$Source = 'C:\Data',
    [string]$Destination = 'D:\Backups',
    [int]$RetainDays = 30
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $target = Join-Path $Destination "Backup_$stamp.zip"

    Compress-Archive -Path $Source -DestinationPath $target -Force

    # Cleanup old backups
    Get-ChildItem -Path $Destination -Filter 'Backup_*.zip' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetainDays) } |
        Remove-Item -Force

    Write-Output "Backup completed: $target"
}
catch {
    Write-Error "Backup failed: $_"
    exit 1
}
