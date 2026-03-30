<#
.SYNOPSIS
    AD-User Provisioning: Anlegen, Aendern, Deaktivieren von AD-Benutzern inkl. Homefolder und Gruppenzuweisung.
.DESCRIPTION
    - Liest Benutzerliste aus CSV (Name, SamAccountName, OU, Gruppen, HomeFolderPfad)
    - Erstellt AD-User mit sicheren Zufalls-Passwort und erzwingt Passwortaenderung beim ersten Login
    - Legt Homefolder an und setzt NTFS-Berechtigungen
    - Weist AD-Gruppen zu
    - Deaktiviert ausgeschiedene User (Offboarding-Modus)
    - Schreibt Log nach C:\Infra\Logs\UserProvisioning_<Datum>.log
.USAGE
    # Onboarding (CSV mit neuen Usern):
    .\Scripts\UserProvisioning.ps1 -Mode Onboard -CsvPath C:\Infra\Config\users_new.csv

    # Offboarding (CSV mit zu deaktivierenden Usern):
    .\Scripts\UserProvisioning.ps1 -Mode Offboard -CsvPath C:\Infra\Config\users_off.csv

    # WhatIf-Trockenlauf:
    .\Scripts\UserProvisioning.ps1 -Mode Onboard -CsvPath .\users.csv -WhatIf
.NOTES
    Voraussetzungen:
      - ActiveDirectory PowerShell-Modul (RSAT oder auf DC)
      - Ausfuehrender Account: Domainadmin oder delegiertes OU-Admin-Recht
    CSV-Format (Onboard):
      SamAccountName,GivenName,Surname,OU,Email,Groups,HomeFolderRoot
      jsmith,John,Smith,"OU=Users,DC=corp,DC=local",jsmith@corp.local,"GRP_VPN;GRP_SharePoint",\\fileserver\homes
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Onboard','Offboard','Report')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$CsvPath,

    # Laenge des generierten Initialpassworts
    [int]$PasswordLength = 16,

    # Homefolder-Laufwerksbuchstabe
    [string]$HomeDrive = 'H:'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Modul-Check
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "ActiveDirectory-Modul nicht gefunden. Bitte RSAT installieren: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
}
Import-Module ActiveDirectory -ErrorAction Stop

# ---------------------------------------------------------------------------
# 1. Logging
# ---------------------------------------------------------------------------
$logDir  = 'C:\Infra\Logs'
$logFile = Join-Path $logDir ("UserProvisioning_{0:yyyyMMdd_HHmm}.log" -f (Get-Date))
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO')
    $entry = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    $entry | Tee-Object -FilePath $logFile -Append | Out-Null
    $color = switch ($Level) { 'OK'{'Green'} 'WARN'{'Yellow'} 'ERROR'{'Red'} default{'White'} }
    Write-Host $entry -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# 2. Hilfsfunktionen
# ---------------------------------------------------------------------------
function New-RandomPassword {
    param([int]$Length = 16)
    $chars  = 'abcdefghijkmnpqrstuvwxyz'
    $upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits = '23456789'
    $special= '!@#$%&*?'
    $all    = $chars + $upper + $digits + $special
    $pwd    = ($upper  | Get-Random) +
              ($digits | Get-Random) +
              ($special| Get-Random) +
              (-join (1..($Length-3) | ForEach-Object { $all | Get-Random }))
    return -join ($pwd.ToCharArray() | Sort-Object { Get-Random })
}

function Set-HomeFolderPermissions {
    param([string]$Path, [string]$SamAccountName, [string]$DomainNetbios = $env:USERDOMAIN)
    $acl  = Get-Acl $Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$DomainNetbios\$SamAccountName",
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.SetAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
}

# ---------------------------------------------------------------------------
# 3. CSV einlesen
# ---------------------------------------------------------------------------
if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV nicht gefunden: $CsvPath" 'ERROR'; exit 1
}
$users = Import-Csv -Path $CsvPath -Encoding UTF8
Write-Log "CSV geladen: $($users.Count) Eintraege - Modus: $Mode" 'INFO'

# ---------------------------------------------------------------------------
# 4. Haupt-Logik
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($u in $users) {
    $sam = $u.SamAccountName.Trim()
    Write-Log "--- $sam ($Mode) ---" 'INFO'

    try {
        switch ($Mode) {

            'Onboard' {
                # Existiert User bereits?
                $existing = Get-ADUser -Filter { SamAccountName -eq $sam } -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-Log "$sam : User existiert bereits - uebersprungen." 'WARN'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='Skipped'; Status='WARN'; Error=$null })
                    continue
                }

                # Passwort generieren
                $plainPwd  = New-RandomPassword -Length $PasswordLength
                $securePwd = ConvertTo-SecureString $plainPwd -AsPlainText -Force

                # AD-User anlegen
                $newUserParams = @{
                    SamAccountName        = $sam
                    GivenName             = $u.GivenName
                    Surname               = $u.Surname
                    Name                  = "$($u.GivenName) $($u.Surname)"
                    DisplayName           = "$($u.GivenName) $($u.Surname)"
                    UserPrincipalName     = $u.Email
                    EmailAddress          = $u.Email
                    Path                  = $u.OU
                    AccountPassword       = $securePwd
                    Enabled               = $true
                    ChangePasswordAtLogon = $true
                    HomeDrive             = $HomeDrive
                }

                if ($PSCmdlet.ShouldProcess($sam, 'AD-User anlegen')) {
                    New-ADUser @newUserParams

                    # Homefolder anlegen + Berechtigungen
                    if ($u.HomeFolderRoot) {
                        $homeFolder = Join-Path $u.HomeFolderRoot $sam
                        if (-not (Test-Path $homeFolder)) {
                            New-Item -ItemType Directory -Path $homeFolder -Force | Out-Null
                        }
                        Set-HomeFolderPermissions -Path $homeFolder -SamAccountName $sam
                        Set-ADUser -Identity $sam -HomeDirectory $homeFolder
                        Write-Log "$sam : Homefolder erstellt: $homeFolder" 'OK'
                    }

                    # Gruppen zuweisen
                    if ($u.Groups) {
                        $u.Groups.Split(';') | Where-Object { $_ } | ForEach-Object {
                            $grp = $_.Trim()
                            try {
                                Add-ADGroupMember -Identity $grp -Members $sam
                                Write-Log "$sam : Gruppe zugewiesen: $grp" 'OK'
                            } catch {
                                Write-Log "$sam : Gruppe '$grp' nicht gefunden - $_" 'WARN'
                            }
                        }
                    }

                    Write-Log "$sam : Onboarding abgeschlossen. Initiales Passwort: $plainPwd" 'OK'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='Created'; Status='OK'; Error=$null })
                }
            }

            'Offboard' {
                $adUser = Get-ADUser -Filter { SamAccountName -eq $sam } -ErrorAction SilentlyContinue
                if (-not $adUser) {
                    Write-Log "$sam : User nicht gefunden." 'WARN'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='NotFound'; Status='WARN'; Error=$null })
                    continue
                }
                if ($PSCmdlet.ShouldProcess($sam, 'AD-User deaktivieren + aus Gruppen entfernen')) {
                    # Deaktivieren
                    Disable-ADAccount -Identity $sam
                    # In Quarantaene-OU verschieben falls angegeben
                    if ($u.PSObject.Properties['DisabledOU'] -and $u.DisabledOU) {
                        Move-ADObject -Identity $adUser.DistinguishedName -TargetPath $u.DisabledOU
                    }
                    # Alle Gruppen entfernen (ausser Domain Users)
                    $groups = Get-ADUser -Identity $sam -Properties MemberOf | Select-Object -ExpandProperty MemberOf
                    $groups | ForEach-Object {
                        try { Remove-ADGroupMember -Identity $_ -Members $sam -Confirm:$false } catch {}
                    }
                    Write-Log "$sam : Offboarding abgeschlossen (deaktiviert, Gruppen entfernt)." 'OK'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='Disabled'; Status='OK'; Error=$null })
                }
            }

            'Report' {
                $adUser = Get-ADUser -Filter { SamAccountName -eq $sam } -Properties * -ErrorAction SilentlyContinue
                if ($adUser) {
                    Write-Log "$sam : Enabled=$($adUser.Enabled)  LastLogon=$($adUser.LastLogonDate)  OU=$($adUser.DistinguishedName)" 'INFO'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='Report'; Status='OK'; Error=$null })
                } else {
                    Write-Log "$sam : Nicht gefunden." 'WARN'
                    $results.Add([PSCustomObject]@{ Sam=$sam; Action='Report'; Status='WARN'; Error='NotFound' })
                }
            }
        }
    }
    catch {
        Write-Log "$sam : FEHLER - $_" 'ERROR'
        $results.Add([PSCustomObject]@{ Sam=$sam; Action=$Mode; Status='FEHLER'; Error=$_.Exception.Message })
    }
}

# ---------------------------------------------------------------------------
# 5. Zusammenfassung
# ---------------------------------------------------------------------------
Write-Log "========== ZUSAMMENFASSUNG ($Mode) ==========" 'INFO'
$ok    = ($results | Where-Object { $_.Status -eq 'OK'     }).Count
$warn  = ($results | Where-Object { $_.Status -eq 'WARN'   }).Count
$error = ($results | Where-Object { $_.Status -eq 'FEHLER' }).Count
Write-Log "OK=$ok  WARN=$warn  FEHLER=$error  Gesamt=$($results.Count)" 'INFO'
Write-Log "Log: $logFile" 'INFO'

return $results
