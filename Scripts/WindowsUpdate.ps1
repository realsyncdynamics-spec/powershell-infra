<#
.SYNOPSIS
    Automatisiertes Windows-Update fuer mehrere Server via PSRemoting.
.DESCRIPTION
    - Liest Serverliste aus Config\servers.json
    - Installiert ausstehende Updates per Invoke-Command (PSWindowsUpdate-Modul)
    - Koordiniert Reboots: ein Server nach dem anderen, mit Wartezeit und Health-Check
    - Schreibt strukturiertes Log nach C:\Infra\Logs\WindowsUpdate_<Datum>.log
.USAGE
    .\Scripts\WindowsUpdate.ps1
    .\Scripts\WindowsUpdate.ps1 -Servers "SRV01","SRV02" -RebootDelay 120 -WhatIf
.NOTES
    Voraussetzungen:
      - PSRemoting auf Zielservern aktiv (Enable-PSRemoting -Force)
      - PSWindowsUpdate-Modul auf Zielservern installiert
        (Install-Module PSWindowsUpdate -Force -Scope AllUsers)
      - Ausfuehrender Account: lokaler Admin oder Domainadmin auf Zielservern
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Optionale direkte Serverliste; wenn leer -> aus Config\servers.json
    [string[]]$Servers,
    # Sekunden Wartezeit nach Reboot bevor naechster Server gepatcht wird
    [int]$RebootDelay = 180,
    # Maximale Wartedauer auf Server-Rueckkehr nach Reboot (Sekunden)
    [int]$RebootTimeout = 600,
    # Nur kritische + sicherheitsrelevante Updates einspielen
    [switch]$SecurityOnly,
    # Kein Reboot, auch wenn Updates es benoetigen
    [switch]$NoReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Logging-Infrastruktur
# ---------------------------------------------------------------------------
$logDir  = 'C:\Infra\Logs'
$logFile = Join-Path $logDir ("WindowsUpdate_{0:yyyyMMdd_HHmm}.log" -f (Get-Date))
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO'
    )
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    $entry | Tee-Object -FilePath $logFile -Append | Out-Null
    $color = switch ($Level) {
        'OK'    { 'Green'  }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red'    }
        default { 'White'  }
    }
    Write-Host $entry -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# 2. Serverliste einlesen
# ---------------------------------------------------------------------------
if (-not $Servers -or $Servers.Count -eq 0) {
    $configPath = Join-Path 'C:\Infra\Config' 'servers.json'
    if (-not (Test-Path $configPath)) {
        Write-Log "servers.json nicht gefunden: $configPath" 'ERROR'
        exit 1
    }
    $config  = Get-Content $configPath -Raw | ConvertFrom-Json
    $Servers = $config.servers | Where-Object { $_.role -ne 'excluded' } | Select-Object -ExpandProperty name
}

Write-Log "Zielserver ($($Servers.Count)): $($Servers -join ', ')" 'INFO'

# ---------------------------------------------------------------------------
# 3. PSWindowsUpdate auf Zielservern sicherstellen
# ---------------------------------------------------------------------------
Write-Log "Pruefe PSWindowsUpdate-Modul auf Zielservern..." 'INFO'

Invoke-Command -ComputerName $Servers -ScriptBlock {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "$env:COMPUTERNAME: Installiere PSWindowsUpdate..." -ForegroundColor Yellow
        Install-Module PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
    }
} -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 4. Updates pro Server installieren
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($server in $Servers) {
    Write-Log "=== $server : Update-Lauf startet ===" 'INFO'

    try {
        $updateParams = @{
            ComputerName  = $server
            AcceptAll     = $true
            IgnoreReboot  = $true    # Reboot steuern wir selbst
            Verbose       = $false
        }
        if ($SecurityOnly) {
            $updateParams['Category'] = @('Security Updates','Critical Updates')
        }

        if ($PSCmdlet.ShouldProcess($server, 'Windows Updates installieren')) {
            $updates = Invoke-Command -ComputerName $server -ScriptBlock {
                param($params)
                Import-Module PSWindowsUpdate -ErrorAction Stop
                Get-WindowsUpdate @params
            } -ArgumentList $updateParams -ErrorAction Stop

            $count = if ($updates) { @($updates).Count } else { 0 }
            Write-Log "$server : $count Update(s) installiert." 'OK'

            # Reboot-Bedarf pruefen
            $rebootNeeded = Invoke-Command -ComputerName $server -ScriptBlock {
                (New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
            }

            if ($rebootNeeded -and -not $NoReboot) {
                Write-Log "$server : Reboot erforderlich - initiiere Neustart..." 'WARN'
                if ($PSCmdlet.ShouldProcess($server, 'Neustart')) {
                    Restart-Computer -ComputerName $server -Force -Wait -For WinRM `
                        -Timeout $RebootTimeout -Delay 10 -ErrorAction Stop
                    Write-Log "$server : Neustart abgeschlossen. Warte $RebootDelay s..." 'OK'
                    Start-Sleep -Seconds $RebootDelay
                }
            } elseif ($rebootNeeded -and $NoReboot) {
                Write-Log "$server : Reboot erforderlich, aber -NoReboot gesetzt. Bitte manuell neu starten." 'WARN'
            }

            $results.Add([PSCustomObject]@{
                Server       = $server
                Updates      = $count
                RebootNeeded = $rebootNeeded
                Status       = 'OK'
                Error        = $null
            })
        }
    }
    catch {
        Write-Log "$server : FEHLER - $_" 'ERROR'
        $results.Add([PSCustomObject]@{
            Server       = $server
            Updates      = 0
            RebootNeeded = $false
            Status       = 'FEHLER'
            Error        = $_.Exception.Message
        })
    }
}

# ---------------------------------------------------------------------------
# 5. Zusammenfassung
# ---------------------------------------------------------------------------
Write-Log "========== ZUSAMMENFASSUNG ==========" 'INFO'
$results | ForEach-Object {
    $lvl = if ($_.Status -eq 'OK') { 'OK' } else { 'ERROR' }
    Write-Log ("{0,-20} Status={1,-8} Updates={2,3}  RebootNeeded={3}" -f `
        $_.Server, $_.Status, $_.Updates, $_.RebootNeeded) $lvl
}
Write-Log "Log gespeichert: $logFile" 'INFO'

# Rueckgabe fuer Pipeline-Nutzung
return $results
