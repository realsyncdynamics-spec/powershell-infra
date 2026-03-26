# powershell-infra

Full PC Automation Toolkit: Desktop, Browser, Server, Apps, Monitoring, Scheduling.

## Quickstart

```powershell
irm https://raw.githubusercontent.com/realsyncdynamics-spec/powershell-infra/main/Deploy-Infra.ps1 | iex
```

## Scripts

| Script | Funktion |
|---|---|
| `DesktopAutomation.ps1` | Maus, Tastatur, Fenster, Screenshots, Clipboard (Win32 API) |
| `AppControl.ps1` | Apps starten/stoppen/installieren, Winget, Startup-Management |
| `BrowserAutomation.ps1` | Selenium + Playwright Setup und Browser-Steuerung |
| `FileSystemWatcher.ps1` | Ordner ueberwachen, auto-copy/move/execute |
| `SystemMonitor.ps1` | CPU, RAM, Disk, Netzwerk - Echtzeit + Alerts (Toast/Email) |
| `ScheduledAutomation.ps1` | Tasks registrieren, Workflows erstellen, orchestrieren |
| `ServerAdmin.ps1` | Remoting, Service-Checks, Backup-Tasks |
| `RemoteDesktop.ps1` | RDP, OpenSSH, WinRM, NLA Konfiguration |
| `backup.ps1` | Zip-Backup mit Retention |

## Beispiele

```powershell
# Desktop steuern
. .\Scripts\DesktopAutomation.ps1
Click-Mouse -X 500 -Y 300
Send-Keys "Hello"
Get-AllWindows | Format-Table
Focus-Window -Title "Notepad"
Take-Screenshot

# Apps verwalten
.\Scripts\AppControl.ps1 -Action List
.\Scripts\AppControl.ps1 -Action Start -AppPath "notepad.exe"
.\Scripts\AppControl.ps1 -Action Stop -AppName "notepad"

# Ordner ueberwachen
.\Scripts\FileSystemWatcher.ps1 -WatchPath C:\Downloads -CopyToPath D:\Backup

# System monitoren
.\Scripts\SystemMonitor.ps1 -IntervalSec 5 -CpuThreshold 80 -Toast -LogToFile

# Workflow erstellen und schedulen
.\Scripts\ScheduledAutomation.ps1 -Action CreateWorkflow -TaskName "NightJob" -WorkflowScripts @("C:\Infra\Scripts\backup.ps1","C:\Infra\Scripts\SystemMonitor.ps1")
.\Scripts\ScheduledAutomation.ps1 -Action Register -TaskName "NightJob" -ScriptPath "C:\Infra\Workflows\NightJob.ps1" -TriggerType Daily -TriggerTime 3am
```

## DSC

```powershell
cd DSC
.\ServerBaseline.ps1 -NodeName SRV01,SRV02
.\Apply-ServerBaseline.ps1 -NodeName SRV01
```

## Lizenz

MIT
