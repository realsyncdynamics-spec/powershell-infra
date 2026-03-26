<#
.SYNOPSIS
    Browser automation setup and examples using Selenium WebDriver + Playwright.
.DESCRIPTION
    - Installs Selenium PowerShell module and ChromeDriver
    - Installs Playwright for .NET (optional)
    - Provides example functions for browser control:
      open URLs, fill forms, click elements, take screenshots
#>

param(
    [switch]$InstallSelenium,
    [switch]$InstallPlaywright,
    [switch]$RunExample
)

$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $PSScriptRoot '..\Logs'
if (-not (Test-Path $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
$logFile = Join-Path $logRoot ("BrowserAutomation_{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Message
    $line | Tee-Object -FilePath $logFile -Append
}

# ---- SELENIUM SETUP ----
if ($InstallSelenium) {
    Write-Log "Installing Selenium PowerShell module..."
    Install-Module -Name Selenium -Force -Scope CurrentUser -AllowClobber

    Write-Log "Downloading ChromeDriver..."
    $chromeDriverPath = Join-Path $PSScriptRoot 'drivers'
    if (-not (Test-Path $chromeDriverPath)) {
        New-Item -ItemType Directory -Path $chromeDriverPath -Force | Out-Null
    }

    # Get latest stable ChromeDriver
    $latestUrl = 'https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_STABLE'
    $version = (Invoke-WebRequest -Uri $latestUrl -UseBasicParsing).Content.Trim()
    $downloadUrl = "https://storage.googleapis.com/chrome-for-testing-public/$version/win64/chromedriver-win64.zip"
    $zipPath = Join-Path $env:TEMP 'chromedriver.zip'

    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $chromeDriverPath -Force
    Remove-Item $zipPath -Force

    Write-Log "Selenium + ChromeDriver installed to $chromeDriverPath"
}

# ---- PLAYWRIGHT SETUP ----
if ($InstallPlaywright) {
    Write-Log "Installing Playwright for PowerShell..."

    # Install .NET tool
    & dotnet tool install --global Microsoft.Playwright.CLI 2>$null
    & playwright install chromium

    Write-Log "Playwright installed. Use 'playwright' CLI or .NET API."
}

# ---- EXAMPLE: Selenium Browser Control ----
if ($RunExample) {
    Write-Log "Running Selenium browser example..."

    Import-Module Selenium

    $driver = Start-SeChrome

    try {
        # Navigate to a URL
        Enter-SeUrl -Driver $driver -Url 'https://www.google.com'
        Start-Sleep -Seconds 2

        # Find search box and type
        $searchBox = Find-SeElement -Driver $driver -Name 'q'
        Send-SeKeys -Element $searchBox -Keys 'PowerShell automation'

        # Submit search
        Send-SeKeys -Element $searchBox -Keys ([OpenQA.Selenium.Keys]::Enter)
        Start-Sleep -Seconds 3

        # Take screenshot
        $screenshotPath = Join-Path $logRoot ("screenshot_{0:yyyyMMdd_HHmmss}.png" -f (Get-Date))
        Save-SeScreenshot -Driver $driver -Path $screenshotPath
        Write-Log "Screenshot saved: $screenshotPath"

        # Get page title
        $title = $driver.Title
        Write-Log "Page title: $title"
    }
    finally {
        Stop-SeDriver -Driver $driver
        Write-Log "Browser closed."
    }
}

<#
.NOTES
    USAGE EXAMPLES:

    # Install Selenium + ChromeDriver
    .\BrowserAutomation.ps1 -InstallSelenium

    # Install Playwright
    .\BrowserAutomation.ps1 -InstallPlaywright

    # Run browser example (opens Chrome, searches Google, takes screenshot)
    .\BrowserAutomation.ps1 -RunExample

    # Remote browser control on another machine:
    Invoke-Command -ComputerName SRV01 -FilePath .\BrowserAutomation.ps1 -ArgumentList @{InstallSelenium=$true}
#>
