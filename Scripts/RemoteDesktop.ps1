<#
.SYNOPSIS
    Enable/configure Remote Desktop and remote computer control on Windows Servers.
.DESCRIPTION
    - Activates RDP
    - Configures NLA (Network Level Authentication)
    - Opens Firewall rules
    - Enables WinRM for PowerShell Remoting
    - Optionally installs and configures OpenSSH for SSH-based remote control
#>

param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [switch]$EnableRDP,
    [switch]$EnableSSH,
    [switch]$EnableWinRM,
    [switch]$DisableNLA
)

$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $PSScriptRoot '..\Logs'
if (-not (Test-Path $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logFile = Join-Path $logRoot ("RemoteDesktop_{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Message
    $line | Tee-Object -FilePath $logFile -Append
}

try {
    Write-Log "Start RemoteDesktop config for: $($ComputerName -join ', ')"

    if ($EnableRDP) {
        Write-Log "Enabling RDP on targets..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            # Enable RDP
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0

            # Enable Firewall rule for RDP
            Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

            # Enable NLA by default (more secure)
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1

            "$env:COMPUTERNAME: RDP enabled with NLA."
        } | ForEach-Object { Write-Log $_ }
    }

    if ($DisableNLA) {
        Write-Log "Disabling NLA (less secure, use only if needed)..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0
            "$env:COMPUTERNAME: NLA disabled."
        } | ForEach-Object { Write-Log $_ }
    }

    if ($EnableWinRM) {
        Write-Log "Enabling WinRM on targets..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Enable-PSRemoting -Force
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
            "$env:COMPUTERNAME: WinRM enabled."
        } | ForEach-Object { Write-Log $_ }
    }

    if ($EnableSSH) {
        Write-Log "Installing and enabling OpenSSH Server..."
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            # Install OpenSSH Server
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

            # Start and set to automatic
            Start-Service sshd
            Set-Service -Name sshd -StartupType Automatic

            # Firewall rule
            New-NetFirewallRule -Name 'OpenSSH-Server' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue

            # Set default shell to PowerShell
            New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force

            "$env:COMPUTERNAME: OpenSSH Server installed and running."
        } | ForEach-Object { Write-Log $_ }
    }

    Write-Log "RemoteDesktop config finished successfully."
}
catch {
    Write-Log "ERROR: $_" 'ERROR'
    throw
}
