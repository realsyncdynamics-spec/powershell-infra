<#
.SYNOPSIS
    Interactive menu to control all powershell-infra modules.
    Run: .\Scripts\AutoPilot.ps1
#>

$root = Split-Path $PSScriptRoot

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host '   powershell-infra AutoPilot' -ForegroundColor Cyan
    Write-Host '   Full PC Automation Toolkit' -ForegroundColor Cyan
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Desktop Automation  (Maus, Tastatur, Fenster)' -ForegroundColor White
    Write-Host '  [2] App Control         (Start, Stop, Install)' -ForegroundColor White
    Write-Host '  [3] Browser Automation  (Selenium/Playwright)' -ForegroundColor White
    Write-Host '  [4] File Watcher        (Ordner ueberwachen)' -ForegroundColor White
    Write-Host '  [5] System Monitor      (CPU, RAM, Disk)' -ForegroundColor White
    Write-Host '  [6] Scheduled Tasks     (Planen, Workflows)' -ForegroundColor White
    Write-Host '  [7] Server Admin        (Remoting, Services)' -ForegroundColor White
    Write-Host '  [8] Remote Desktop      (RDP, SSH, WinRM)' -ForegroundColor White
    Write-Host '  [9] Backup              (Zip + Retention)' -ForegroundColor White
    Write-Host '  [0] Exit' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Desktop {
    Write-Host '  Loading DesktopAutomation...' -ForegroundColor Yellow
    . "$PSScriptRoot\DesktopAutomation.ps1"
    Write-Host '  Functions loaded. Available:' -ForegroundColor Green
    Write-Host '    Click-Mouse -X 500 -Y 300'
    Write-Host '    Send-Keys "text"'
    Write-Host '    Get-AllWindows | Format-Table'
    Write-Host '    Focus-Window -Title "Notepad"'
    Write-Host '    Take-Screenshot'
    Write-Host '    Set-ClipboardText / Get-ClipboardText'
    Write-Host ''
    Write-Host '  Type commands interactively. Type "menu" to return.' -ForegroundColor Cyan
    while ($true) {
        $cmd = Read-Host '  PS Infra'
        if ($cmd -eq 'menu') { return }
        try { Invoke-Expression $cmd } catch { Write-Warning $_.Exception.Message }
    }
}

function Invoke-AppControl {
    Write-Host '  [a] List running apps' -ForegroundColor White
    Write-Host '  [b] Start app' -ForegroundColor White
    Write-Host '  [c] Stop app' -ForegroundColor White
    Write-Host '  [d] List installed apps' -ForegroundColor White
    $choice = Read-Host '  Choice'
    switch ($choice) {
        'a' { & "$PSScriptRoot\AppControl.ps1" -Action List }
        'b' { $p = Read-Host '  App path'; & "$PSScriptRoot\AppControl.ps1" -Action Start -AppPath $p }
        'c' { $n = Read-Host '  Process name'; & "$PSScriptRoot\AppControl.ps1" -Action Stop -AppName $n }
        'd' { . "$PSScriptRoot\AppControl.ps1"; Get-InstalledApps | Format-Table -AutoSize }
    }
}

function Invoke-BrowserAuto {
    Write-Host '  [a] Install Selenium' -ForegroundColor White
    Write-Host '  [b] Run browser example' -ForegroundColor White
    $choice = Read-Host '  Choice'
    switch ($choice) {
        'a' { & "$PSScriptRoot\BrowserAutomation.ps1" -InstallSelenium }
        'b' { & "$PSScriptRoot\BrowserAutomation.ps1" -RunExample }
    }
}

function Invoke-FileWatch {
    $path = Read-Host '  Watch path (e.g. C:\Downloads)'
    $copy = Read-Host '  Copy to (leave empty to skip)'
    $args = @{ WatchPath = $path }
    if ($copy) { $args.CopyToPath = $copy }
    & "$PSScriptRoot\FileSystemWatcher.ps1" @args
}

function Invoke-SysMon {
    Write-Host '  Starting SystemMonitor (Ctrl+C to stop)...' -ForegroundColor Yellow
    & "$PSScriptRoot\SystemMonitor.ps1" -IntervalSec 3 -Toast -LogToFile
}

function Invoke-Scheduler {
    Write-Host '  [a] List tasks' -ForegroundColor White
    Write-Host '  [b] Register new task' -ForegroundColor White
    Write-Host '  [c] Run task now' -ForegroundColor White
    Write-Host '  [d] Create workflow' -ForegroundColor White
    $choice = Read-Host '  Choice'
    switch ($choice) {
        'a' { & "$PSScriptRoot\ScheduledAutomation.ps1" -Action List }
        'b' {
            $name = Read-Host '  Task name'
            $script = Read-Host '  Script path'
            $time = Read-Host '  Time (e.g. 3am)'
            & "$PSScriptRoot\ScheduledAutomation.ps1" -Action Register -TaskName $name -ScriptPath $script -TriggerTime $time
        }
        'c' { $n = Read-Host '  Task name'; & "$PSScriptRoot\ScheduledAutomation.ps1" -Action RunNow -TaskName $n }
        'd' {
            $name = Read-Host '  Workflow name'
            $scripts = (Read-Host '  Scripts (comma-separated)') -split ','
            & "$PSScriptRoot\ScheduledAutomation.ps1" -Action CreateWorkflow -TaskName $name -WorkflowScripts $scripts
        }
    }
}

function Invoke-ServerAdmin {
    $srv = (Read-Host '  Server(s) comma-separated') -split ','
    Write-Host '  [a] Enable Remoting  [b] Check Spooler  [c] Register Backup' -ForegroundColor White
    $choice = Read-Host '  Choice'
    switch ($choice) {
        'a' { & "$PSScriptRoot\ServerAdmin.ps1" -ComputerName $srv -EnableRemoting }
        'b' { & "$PSScriptRoot\ServerAdmin.ps1" -ComputerName $srv -CheckSpooler }
        'c' { & "$PSScriptRoot\ServerAdmin.ps1" -ComputerName $srv -RegisterBackupTask }
    }
}

function Invoke-RDP {
    $srv = (Read-Host '  Server(s) comma-separated') -split ','
    Write-Host '  [a] Enable RDP  [b] Enable SSH  [c] Enable WinRM' -ForegroundColor White
    $choice = Read-Host '  Choice'
    switch ($choice) {
        'a' { & "$PSScriptRoot\RemoteDesktop.ps1" -ComputerName $srv -EnableRDP }
        'b' { & "$PSScriptRoot\RemoteDesktop.ps1" -ComputerName $srv -EnableSSH }
        'c' { & "$PSScriptRoot\RemoteDesktop.ps1" -ComputerName $srv -EnableWinRM }
    }
}

function Invoke-Backup {
    $src = Read-Host '  Source (default: C:\Data)'
    $dst = Read-Host '  Destination (default: D:\Backups)'
    $args = @{}
    if ($src) { $args.Source = $src }
    if ($dst) { $args.Destination = $dst }
    & "$PSScriptRoot\backup.ps1" @args
}

# Main loop
while ($true) {
    Show-Menu
    $selection = Read-Host '  Select [0-9]'
    switch ($selection) {
        '1' { Invoke-Desktop }
        '2' { Invoke-AppControl }
        '3' { Invoke-BrowserAuto }
        '4' { Invoke-FileWatch }
        '5' { Invoke-SysMon }
        '6' { Invoke-Scheduler }
        '7' { Invoke-ServerAdmin }
        '8' { Invoke-RDP }
        '9' { Invoke-Backup }
        '0' { Write-Host '  Bye!' -ForegroundColor Green; exit }
        default { Write-Host '  Invalid choice.' -ForegroundColor Red }
    }
    Write-Host ''
    Read-Host '  Press Enter to return to menu'
}
