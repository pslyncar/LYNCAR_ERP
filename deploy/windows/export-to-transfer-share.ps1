param(
    [Parameter(Mandatory = $true)]
    [string]$SharePath,

    [string]$VaultPath = "D:\MEU CEREBRO\CEREBRO",

    [switch]$IncludeVault
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PackageRoot = Join-Path $env:TEMP "lynkar-export-$Timestamp"
$ProjectPackageDir = Join-Path $PackageRoot "ERP-PAPEZZOSYNC"
$OutputDir = Join-Path $SharePath "lynkar-export-$Timestamp"

if (-not (Test-Path $SharePath)) {
    throw "Pasta de rede nao encontrada: $SharePath"
}

New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$excludeDirs = @(
    ".git",
    ".dart_tool",
    "build",
    ".venv",
    "__pycache__",
    ".pytest_cache",
    "dist"
)

Write-Host "Copiando projeto para pacote temporario..."
robocopy $ProjectRoot $ProjectPackageDir /E /XD $excludeDirs /XF "*.pyc" "*.log" | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "Falha ao copiar projeto com robocopy. Codigo: $LASTEXITCODE"
}

$projectZip = Join-Path $OutputDir "ERP-PAPEZZOSYNC-$Timestamp.zip"
Write-Host "Compactando projeto em $projectZip..."
Compress-Archive -LiteralPath $ProjectPackageDir -DestinationPath $projectZip -Force

if ($IncludeVault) {
    if (-not (Test-Path $VaultPath)) {
        throw "Vault nao encontrado: $VaultPath"
    }
    $vaultZip = Join-Path $OutputDir "CEREBRO-$Timestamp.zip"
    Write-Host "Compactando Vault Obsidian em $vaultZip..."
    Compress-Archive -LiteralPath $VaultPath -DestinationPath $vaultZip -Force
}

$readmePath = Join-Path $OutputDir "LEIA-ME-SERVIDOR.txt"
@"
Pacote Lynkar/PapezzoSync gerado em $Timestamp.

No servidor Windows 11 Pro:

1. Extraia ERP-PAPEZZOSYNC-$Timestamp.zip para:
   C:\Lynkar\ERP-PAPEZZOSYNC

2. Abra PowerShell como administrador.

3. Rode:
   cd C:\Lynkar\ERP-PAPEZZOSYNC
   .\deploy\windows\server-install.ps1

4. Edite:
   C:\Lynkar\ERP-PAPEZZOSYNC\backend\.env

5. Depois rode:
   .\deploy\windows\server-update.ps1
   .\deploy\windows\server-start.ps1

6. Login master:
   Empresa: master
   E-mail: definido no backend\.env
   Senha: definida no backend\.env

Observacao:
- Esta pasta compartilhada deve ser usada so como ponte de transferencia.
- O sistema deve rodar localmente em C:\Lynkar\ERP-PAPEZZOSYNC no servidor.
"@ | Set-Content -LiteralPath $readmePath -Encoding UTF8

Remove-Item -LiteralPath $PackageRoot -Recurse -Force

Write-Host ""
Write-Host "Exportacao concluida:"
Write-Host $OutputDir
