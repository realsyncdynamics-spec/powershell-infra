# powershell-infra

PowerShell Server-Automatisierung: Remoting, Desktop-Steuerung, Browser-Automation, DSC

## Quickstart

```powershell
# Bootstrap - clont das Repo nach C:\Infra
irm https://raw.githubusercontent.com/realsyncdynamics-spec/powershell-infra/main/Deploy-Infra.ps1 | iex
```

## Struktur

```
powershell-infra/
|-- Config/
|   +-- servers.json
|-- DSC/
|   |-- ServerBaseline.ps1
|   |-- Test-ServerBaseline.ps1
|   +-- Apply-ServerBaseline.ps1
|-- Scripts/
|   |-- ServerAdmin.ps1
|   |-- RemoteDesktop.ps1
|   |-- BrowserAutomation.ps1
|   +-- backup.ps1
|-- Deploy-Infra.ps1
+-- README.md
```

## Scripts

### ServerAdmin.ps1
Remoting, Service-Checks, Backup-Task Registration.
```powershell
.\Scripts\ServerAdmin.ps1 -ComputerName SRV01,SRV02 -EnableRemoting
.\Scripts\ServerAdmin.ps1 -ComputerName SRV01 -CheckSpooler
.\Scripts\ServerAdmin.ps1 -ComputerName SRV01 -RegisterBackupTask
```

### RemoteDesktop.ps1
RDP, OpenSSH, WinRM, NLA Konfiguration.
```powershell
.\Scripts\RemoteDesktop.ps1 -ComputerName SRV01 -EnableRDP -EnableSSH
.\Scripts\RemoteDesktop.ps1 -ComputerName SRV01 -EnableWinRM
```

### BrowserAutomation.ps1
Selenium WebDriver + Playwright Setup und Beispiele.
```powershell
.\Scripts\BrowserAutomation.ps1 -InstallSelenium
.\Scripts\BrowserAutomation.ps1 -RunExample
```

### backup.ps1
Zip-Backup mit automatischer Retention.
```powershell
.\Scripts\backup.ps1 -Source C:\Data -Destination D:\Backups -RetainDays 30
```

## DSC (Desired State Configuration)

```powershell
# MOFs generieren
cd DSC
.\ServerBaseline.ps1 -NodeName SRV01,SRV02

# Testen (WhatIf)
.\Test-ServerBaseline.ps1 -NodeName SRV01

# Anwenden
.\Apply-ServerBaseline.ps1 -NodeName SRV01
```

Enthaltene Ressourcen: IIS, RDP, NLA, WinRM, Registry (RealSyncDynamics Environment Tag).

## Lizenz

MIT
