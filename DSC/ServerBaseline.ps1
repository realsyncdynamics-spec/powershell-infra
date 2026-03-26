param(
    [string[]]$NodeName,
    [string]$WebsiteFilePath = '\\share\web'
)

Configuration ServerBaseline {
    param(
        [string[]]$NodeName,
        [string]$WebsiteFilePath
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $NodeName {

        WindowsFeature IIS {
            Ensure = 'Present'
            Name   = 'Web-Server'
        }

        File WebDirectory {
            Ensure          = 'Present'
            Type            = 'Directory'
            Recurse         = $true
            SourcePath      = $WebsiteFilePath
            DestinationPath = 'C:\inetpub\wwwroot'
            DependsOn       = '[WindowsFeature]IIS'
        }

        Service SpoolerService {
            Name   = 'Spooler'
            Ensure = 'Present'
            State  = 'Running'
        }

        Registry EnableRDP {
            Ensure    = 'Present'
            Key       = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
            ValueName = 'fDenyTSConnections'
            ValueData = '0'
            ValueType = 'Dword'
        }

        Registry EnableNLA {
            Ensure    = 'Present'
            Key       = 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
            ValueName = 'UserAuthentication'
            ValueData = '1'
            ValueType = 'Dword'
        }

        Registry EnvSetting {
            Ensure    = 'Present'
            Key       = 'HKLM:\SOFTWARE\RealSyncDynamics'
            ValueName = 'Environment'
            ValueData = 'Production'
            ValueType = 'String'
        }

        Service WinRM {
            Name   = 'WinRM'
            Ensure = 'Present'
            State  = 'Running'
        }
    }
}

ServerBaseline -NodeName $NodeName -WebsiteFilePath $WebsiteFilePath
