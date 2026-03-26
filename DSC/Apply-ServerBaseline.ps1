param(
    [Parameter(Mandatory)]
    [string]$NodeName
)

$configPath = Join-Path $PSScriptRoot 'ServerBaseline'

if (-not (Test-Path $configPath)) {
    Write-Warning "MOF not found. Run ServerBaseline.ps1 first."
    exit 1
}

Start-DscConfiguration -Path $configPath -ComputerName $NodeName -Wait -Verbose -Force
