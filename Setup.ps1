<#
.SYNOPSIS
    One-Click Setup: Installiert powershell-infra auf deinem PC.
    Fuehre aus: irm https://raw.githubusercontent.com/realsyncdynamics-spec/powershell-infra/main/Setup.ps1 | iex
#>

$ErrorActionPreference = 'Stop'
$root = 'C:\Infra'
$repoUrl = 'https://github.com/realsyncdynamics-spec/powershell-infra.git'
$repoZip = 'https://github.com/realsyncdynamics-spec/powershell-infra/archive/refs/heads/main.zip'

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  powershell-infra Setup' -ForegroundColor Cyan
Write-Host '  Full PC Automation Toolkit' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# 1. Execution Policy
Write-Host '[1/5] Setting ExecutionPolicy...' -ForegroundColor Yellow
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Write-Host '      Done.' -ForegroundColor Green

# 2. Create folder structure
Write-Host '[2/5] Creating folder structure...' -ForegroundColor Yellow
'Scripts','Logs','Config','DSC','Workflows' | ForEach-Object {
    $p = Join-Path $root $_
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
Write-Host '      Done.' -ForegroundColor Green

# 3. Clone or download repo
Write-Host '[3/5] Downloading toolkit...' -ForegroundColor Yellow
if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $root '.git')) {
        Push-Location $root
        git pull --quiet
        Pop-Location
        Write-Host '      Git pull complete.' -ForegroundColor Green
    } else {
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        git clone --quiet $repoUrl $root
        Write-Host '      Git clone complete.' -ForegroundColor Green
    }
} else {
    Write-Host '      Git not found, downloading ZIP...' -ForegroundColor DarkYellow
    $zipPath = Join-Path $env:TEMP 'powershell-infra.zip'
    $extractPath = Join-Path $env:TEMP 'powershell-infra-extract'
    Invoke-WebRequest -Uri $repoZip -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    $source = Join-Path $extractPath 'powershell-infra-main'
    Copy-Item -Path "$source\*" -Destination $root -Recurse -Force
    Remove-Item $zipPath, $extractPath -Recurse -Force
    Write-Host '      ZIP download complete.' -ForegroundColor Green
}

# 4. Create desktop shortcut
Write-Host '[4/5] Creating desktop shortcut...' -ForegroundColor Yellow
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'PowerShell-Infra.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoExit -ExecutionPolicy RemoteSigned -Command `"cd C:\Infra; Write-Host 'powershell-infra ready. Type: . .\Scripts\DesktopAutomation.ps1' -ForegroundColor Green`""
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = 'powershell.exe,0'
$shortcut.Save()
Write-Host '      Desktop shortcut created.' -ForegroundColor Green

# 5. Verify
Write-Host '[5/5] Verifying installation...' -ForegroundColor Yellow
$scripts = Get-ChildItem -Path (Join-Path $root 'Scripts') -Filter '*.ps1' -ErrorAction SilentlyContinue
Write-Host "      Found $($scripts.Count) scripts in C:\Infra\Scripts" -ForegroundColor Green

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host '  Setup complete!' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Write-Host ''
Write-Host 'Installed to: C:\Infra' -ForegroundColor White
Write-Host 'Desktop shortcut: PowerShell-Infra' -ForegroundColor White
Write-Host ''
Write-Host 'Quick start:' -ForegroundColor Cyan
Write-Host '  cd C:\Infra' -ForegroundColor White
Write-Host '  . .\Scripts\DesktopAutomation.ps1' -ForegroundColor White
Write-Host '  Get-AllWindows | Format-Table' -ForegroundColor White
Write-Host '  .\Scripts\AppControl.ps1 -Action List' -ForegroundColor White
Write-Host '  .\Scripts\AutoPilot.ps1' -ForegroundColor White
Write-Host ''
