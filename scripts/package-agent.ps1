$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root "agent"
$dist = Join-Path $root "dist"
$packageDir = Join-Path $dist "papezzosync-agent"
$zipPath = Join-Path $dist "papezzosync-agent.zip"

if (Test-Path $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}

New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

Copy-Item -Path (Join-Path $source "papezzosync_agent") -Destination $packageDir -Recurse -Force
Get-ChildItem -Path $packageDir -Directory -Recurse -Filter "__pycache__" |
    Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $source "requirements.txt") -Destination $packageDir -Force
Copy-Item -Path (Join-Path $source "config.example.json") -Destination $packageDir -Force
Copy-Item -Path (Join-Path $source "install-windows.ps1") -Destination $packageDir -Force
Copy-Item -Path (Join-Path $source "uninstall-windows.ps1") -Destination $packageDir -Force
Copy-Item -Path (Join-Path $source "README.md") -Destination $packageDir -Force

if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $zipPath

Write-Host "Pacote criado:"
Write-Host $zipPath
