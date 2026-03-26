<#
.SYNOPSIS
    Application lifecycle control: Start, stop, restart, install,
    uninstall apps. Process management and monitoring.
#>

param(
    [string]$Action,     # Start, Stop, Restart, Kill, List, Install, Uninstall
    [string]$AppName,
    [string]$AppPath,
    [string[]]$Args,
    [string]$InstallerPath,
    [string]$InstallerArgs = '/S',
    [switch]$AsAdmin
)

$ErrorActionPreference = 'Stop'

# --- PROCESS FUNCTIONS ---
function Start-App {
    param([string]$Path, [string[]]$Arguments, [switch]$Elevated)
    if ($Elevated) {
        Start-Process -FilePath $Path -ArgumentList $Arguments -Verb RunAs
    } else {
        Start-Process -FilePath $Path -ArgumentList $Arguments
    }
    Write-Output "Started: $Path"
}

function Stop-App {
    param([string]$Name)
    $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Output "Stopped $($procs.Count) instance(s) of $Name"
    } else { Write-Warning "No process '$Name' found." }
}

function Restart-App {
    param([string]$Name, [string]$Path)
    Stop-App -Name $Name
    Start-Sleep -Seconds 2
    Start-App -Path $Path
}

function Get-RunningApps {
    Get-Process | Where-Object { $_.MainWindowTitle } |
        Select-Object Id, ProcessName, MainWindowTitle, @{N='CPU_s';E={[math]::Round($_.CPU,1)}}, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}} |
        Sort-Object RAM_MB -Descending
}

function Wait-ForApp {
    param([string]$Name, [int]$TimeoutSec = 30)
    $elapsed = 0
    while (-not (Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 1
        $elapsed++
        if ($elapsed -ge $TimeoutSec) { Write-Warning "Timeout waiting for $Name"; return $false }
    }
    return $true
}

# --- INSTALL / UNINSTALL ---
function Install-App {
    param([string]$Installer, [string]$SilentArgs = '/S')
    Write-Output "Installing: $Installer"
    Start-Process -FilePath $Installer -ArgumentList $SilentArgs -Wait -Verb RunAs
    Write-Output "Installation complete."
}

function Uninstall-App {
    param([string]$DisplayName)
    $app = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
           Where-Object { $_.DisplayName -like "*$DisplayName*" } | Select-Object -First 1
    if ($app -and $app.UninstallString) {
        Write-Output "Uninstalling: $($app.DisplayName)"
        Start-Process cmd -ArgumentList "/c $($app.UninstallString) /S" -Wait -Verb RunAs
    } else { Write-Warning "App '$DisplayName' not found in registry." }
}

function Get-InstalledApps {
    Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName
}

# --- WINGET INTEGRATION ---
function Winget-Install { param([string]$PackageId); winget install --id $PackageId --accept-source-agreements --accept-package-agreements }
function Winget-Update  { param([string]$PackageId); winget upgrade --id $PackageId }
function Winget-Remove  { param([string]$PackageId); winget uninstall --id $PackageId }
function Winget-Search  { param([string]$Query); winget search $Query }

# --- STARTUP MANAGEMENT ---
function Get-StartupApps {
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
}

function Add-StartupApp {
    param([string]$Name, [string]$Path)
    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $regPath -Name $Name -Value $Path
    Write-Output "Added '$Name' to startup."
}

function Remove-StartupApp {
    param([string]$Name)
    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Remove-ItemProperty -Path $regPath -Name $Name -ErrorAction SilentlyContinue
    Write-Output "Removed '$Name' from startup."
}

# --- DISPATCH ---
switch ($Action) {
    'Start'     { Start-App -Path $AppPath -Arguments $Args -Elevated:$AsAdmin }
    'Stop'      { Stop-App -Name $AppName }
    'Restart'   { Restart-App -Name $AppName -Path $AppPath }
    'Kill'      { Stop-App -Name $AppName }
    'List'      { Get-RunningApps | Format-Table -AutoSize }
    'Install'   { Install-App -Installer $InstallerPath -SilentArgs $InstallerArgs }
    'Uninstall' { Uninstall-App -DisplayName $AppName }
    default     { Write-Output 'Actions: Start, Stop, Restart, Kill, List, Install, Uninstall' }
}
