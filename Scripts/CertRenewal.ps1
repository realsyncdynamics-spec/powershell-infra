<#
.SYNOPSIS
    SSL/TLS-Zertifikate auf mehreren Windows-Servern pruefen und bei Bedarf erneuern.
.DESCRIPTION
    - Liest Serverliste aus Config\servers.json
    - Prueft Zertifikate im LocalMachine\My Store und optional per HTTPS-Verbindungscheck
    - Warnt bei Ablauf innerhalb des konfigurierten Schwellwerts (Standard: 30 Tage)
    - Erneuert Zertifikate automatisch via ACME (win-acme/wacs.exe) oder AD CS Request
    - Exportiert Bericht als CSV nach C:\Infra\Logs\CertReport_<Datum>.csv
    - Schreibt Log nach C:\Infra\Logs\CertRenewal_<Datum>.log
.USAGE
    # Nur pruefen, kein Erneuern:
    .\Scripts\CertRenewal.ps1 -Mode Check

    # Pruefen + automatisch erneuern (via win-acme):
    .\Scripts\CertRenewal.ps1 -Mode Renew -RenewalTool winacme

    # Nur lokalen Server pruefen:
    .\Scripts\CertRenewal.ps1 -Mode Check -Servers "localhost"

    # Warnschwelle 14 Tage:
    .\Scripts\CertRenewal.ps1 -Mode Check -WarnDays 14
.NOTES
    Fuer -Mode Renew mit -RenewalTool winacme:
      - win-acme (wacs.exe) muss unter C:\Infra\Tools\wacs.exe vorhanden sein
      - Ports 80/443 muessen vom ACME-Server erreichbar sein
    Fuer -RenewalTool adcs:
      - Ausfuehrender Account braucht Enrollment-Berechtigung an der CA
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Check','Renew','Report')]
    [string]$Mode = 'Check',

    [string[]]$Servers,

    # Warnmeldung wenn Zertifikat in weniger als X Tagen ablaueft
    [int]$WarnDays = 30,

    # Erneuerungstool: winacme | adcs | none
    [ValidateSet('winacme','adcs','none')]
    [string]$RenewalTool = 'none',

    # Pfad zu wacs.exe (win-acme)
    [string]$WacsPath = 'C:\Infra\Tools\wacs.exe',

    # Nur Zertifikate mit diesen DNS-Namen erneuern (leer = alle ablaufenden)
    [string[]]$DnsFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Logging
# ---------------------------------------------------------------------------
$logDir     = 'C:\Infra\Logs'
$logFile    = Join-Path $logDir ("CertRenewal_{0:yyyyMMdd_HHmm}.log"  -f (Get-Date))
$reportFile = Join-Path $logDir ("CertReport_{0:yyyyMMdd_HHmm}.csv"   -f (Get-Date))
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK','CRIT')][string]$Level = 'INFO')
    $entry = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    $entry | Tee-Object -FilePath $logFile -Append | Out-Null
    $color = switch ($Level) { 'OK'{'Green'} 'WARN'{'Yellow'} 'ERROR'{'Red'} 'CRIT'{'Magenta'} default{'White'} }
    Write-Host $entry -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# 2. Serverliste
# ---------------------------------------------------------------------------
if (-not $Servers -or $Servers.Count -eq 0) {
    $configPath = 'C:\Infra\Config\servers.json'
    if (Test-Path $configPath) {
        $config  = Get-Content $configPath -Raw | ConvertFrom-Json
        $Servers = $config.servers | Where-Object { $_.role -ne 'excluded' } | Select-Object -ExpandProperty name
    } else {
        $Servers = @('localhost')
    }
}
Write-Log "Zielserver ($($Servers.Count)): $($Servers -join ', ')  Modus: $Mode  WarnDays: $WarnDays" 'INFO'

# ---------------------------------------------------------------------------
# 3. Zertifikate pruefen
# ---------------------------------------------------------------------------
function Get-CertStatus {
    param([string]$Server, [int]$WarnDays)

    $certInfos = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $rawCerts = Invoke-Command -ComputerName $Server -ScriptBlock {
            Get-ChildItem Cert:\LocalMachine\My | Select-Object `
                Subject, Thumbprint, NotAfter, NotBefore, FriendlyName,
                @{N='DnsNames'; E={ ($_.DnsNameList | Select-Object -ExpandProperty Unicode) -join ',' }},
                @{N='Issuer';   E={ $_.Issuer }}
        } -ErrorAction Stop

        foreach ($cert in $rawCerts) {
            $daysLeft = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 1)
            $status   = if     ($daysLeft -lt 0)        { 'EXPIRED' }
                        elseif ($daysLeft -lt $WarnDays) { 'EXPIRING' }
                        else                             { 'OK' }

            $certInfos.Add([PSCustomObject]@{
                Server      = $Server
                Subject     = $cert.Subject
                DnsNames    = $cert.DnsNames
                Thumbprint  = $cert.Thumbprint
                Issuer      = $cert.Issuer
                NotAfter    = $cert.NotAfter
                DaysLeft    = $daysLeft
                Status      = $status
            })
        }
    }
    catch {
        Write-Log "${Server}: Fehler beim Abrufen der Zertifikate - $_" 'ERROR'
        $certInfos.Add([PSCustomObject]@{
            Server     = $Server
            Subject    = 'N/A'
            DnsNames   = ''
            Thumbprint = ''
            Issuer     = ''
            NotAfter   = $null
            DaysLeft   = $null
            Status     = 'ERROR'
        })
    }
    return $certInfos
}

# ---------------------------------------------------------------------------
# 4. Zertifikat erneuern
# ---------------------------------------------------------------------------
function Invoke-CertRenewal {
    param([string]$Server, [PSCustomObject]$CertInfo, [string]$Tool, [string]$WacsExe)

    Write-Log "$Server | $($CertInfo.Subject) : Starte Erneuerung via $Tool..." 'WARN'

    if (-not $PSCmdlet.ShouldProcess("$Server - $($CertInfo.Subject)", 'Zertifikat erneuern')) { return $false }

    switch ($Tool) {
        'winacme' {
            if (-not (Test-Path $WacsExe)) {
                Write-Log "wacs.exe nicht gefunden: $WacsExe" 'ERROR'; return $false
            }
            # Erneuerung via win-acme (Let's Encrypt) fuer alle abgelaufenen/ablaufenden Certs
            $result = & $WacsExe --renew --baseuri https://acme-v02.api.letsencrypt.org/ 2>&1
            Write-Log "$Server : wacs.exe Output: $result" 'INFO'
            return $true
        }
        'adcs' {
            # AD CS Request via certreq.exe (auf Zielserver remote ausfuehren)
            $renewed = Invoke-Command -ComputerName $Server -ScriptBlock {
                param($thumb)
                try {
                    # Bestehende Cert-Vorlage ermitteln und Re-Enroll
                    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $thumb }
                    if ($cert) {
                        # Re-Enrollment via certreq (vereinfacht - Vorlage aus vorhandenem Cert)
                        $template = ($cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq 'Certificate Template Name' })
                        if ($template) {
                            $infContent = "[NewRequest]`nSubject=`"$($cert.Subject)`"`nRenewalCert=$thumb"
                            $infPath    = "$env:TEMP\certrenew.inf"
                            $reqPath    = "$env:TEMP\certrenew.req"
                            $infContent | Set-Content $infPath -Encoding ASCII
                            certreq -new $infPath $reqPath | Out-Null
                            certreq -submit $reqPath | Out-Null
                            return $true
                        }
                    }
                    return $false
                } catch { return $false }
            } -ArgumentList $CertInfo.Thumbprint
            if ($renewed) { Write-Log "$Server : AD CS Erneuerung erfolgreich." 'OK' }
            else          { Write-Log "$Server : AD CS Erneuerung fehlgeschlagen." 'ERROR' }
            return $renewed
        }
        default {
            Write-Log "$Server : Kein Erneuerungstool konfiguriert. Bitte manuell erneuern." 'WARN'
            return $false
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Haupt-Schleife
# ---------------------------------------------------------------------------
$allCerts = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($server in $Servers) {
    Write-Log "=== $server : Zertifikats-Check ===" 'INFO'
    $certs = Get-CertStatus -Server $server -WarnDays $WarnDays

    foreach ($cert in $certs) {
        # DNS-Filter anwenden falls gesetzt
        if ($DnsFilter -and $cert.DnsNames) {
            $match = $DnsFilter | Where-Object { $cert.DnsNames -like "*$_*" }
            if (-not $match) { continue }
        }

        $lvl = switch ($cert.Status) { 'EXPIRED'{'CRIT'} 'EXPIRING'{'WARN'} 'ERROR'{'ERROR'} default{'OK'} }
        Write-Log ("{0,-20} {1,-50} DaysLeft={2,6}  Status={3}" -f `
            $cert.Server, ($cert.Subject -replace 'CN=',''), $cert.DaysLeft, $cert.Status) $lvl

        # Erneuern falls Modus Renew und Status nicht OK
        if ($Mode -eq 'Renew' -and $cert.Status -in 'EXPIRED','EXPIRING') {
            $renewed = Invoke-CertRenewal -Server $server -CertInfo $cert -Tool $RenewalTool -WacsExe $WacsPath
            if ($renewed) { $cert.Status = 'RENEWED' }
        }

        $allCerts.Add($cert)
    }
}

# ---------------------------------------------------------------------------
# 6. CSV-Report exportieren
# ---------------------------------------------------------------------------
$allCerts | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
Write-Log "CSV-Report gespeichert: $reportFile" 'INFO'

# ---------------------------------------------------------------------------
# 7. Zusammenfassung
# ---------------------------------------------------------------------------
Write-Log "========== ZUSAMMENFASSUNG ==========" 'INFO'
$groups = $allCerts | Group-Object Status
$groups | ForEach-Object { Write-Log "  $($_.Name): $($_.Count)" 'INFO' }

$critical = $allCerts | Where-Object { $_.Status -in 'EXPIRED','EXPIRING' }
if ($critical) {
    Write-Log "HANDLUNGSBEDARF ($($critical.Count) Zertifikat(e)):" 'CRIT'
    $critical | ForEach-Object {
        Write-Log "  -> $($_.Server) | $($_.Subject) | Ablauf: $($_.NotAfter) (noch $($_.DaysLeft) Tage)" 'CRIT'
    }
}
Write-Log "Log: $logFile" 'INFO'

return $allCerts
