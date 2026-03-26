<#
.SYNOPSIS
    Bootstrap: Clone repo and deploy to C:\Infra locally.
#>

$root = 'C:\Infra'
$repoUrl = 'https://github.com/realsyncdynamics-spec/powershell-infra.git'

# Create local structure
'Scripts','Logs','Config','DSC' | ForEach-Object {
    $p = Join-Path $root $_
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# Clone or pull repo
if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $root '.git')) {
        Set-Location $root
        git pull
    } else {
        git clone $repoUrl $root
    }
} else {
    Write-Warning 'Git not found. Install git or download repo manually.'
}

Write-Host 'Deploy-Infra complete. Structure:' -ForegroundColor Green
Get-ChildItem $root -Recurse -Depth 2 | Format-Table FullName
