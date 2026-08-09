$ErrorActionPreference = "Stop"

$InstallRoot = "C:\Lynkar"
$ProjectRoot = Join-Path $InstallRoot "ERP-PAPEZZOSYNC"
$BackendRoot = Join-Path $ProjectRoot "backend"
$FlutterRoot = Join-Path $ProjectRoot "admin_app\admin_flutter"

Write-Host "Preparando pastas em $InstallRoot..."
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "backups") | Out-Null

if (-not (Test-Path $ProjectRoot)) {
    Write-Host "Copie ou clone o projeto para: $ProjectRoot"
    Write-Host "Depois rode este script novamente."
    exit 1
}

if (-not (Test-Path (Join-Path $BackendRoot ".env"))) {
    Copy-Item `
        -LiteralPath (Join-Path $ProjectRoot "deploy\windows\.env.production.example") `
        -Destination (Join-Path $BackendRoot ".env")
    Write-Host "Criado backend\.env. Edite as senhas antes de continuar."
    exit 1
}

Write-Host "Criando ambiente Python..."
if (-not (Test-Path (Join-Path $BackendRoot ".venv\Scripts\python.exe"))) {
    py -3 -m venv (Join-Path $BackendRoot ".venv")
}

& (Join-Path $BackendRoot ".venv\Scripts\python.exe") -m pip install --upgrade pip
& (Join-Path $BackendRoot ".venv\Scripts\pip.exe") install -r (Join-Path $BackendRoot "requirements.txt")

Write-Host "Aplicando migracoes..."
& (Join-Path $BackendRoot ".venv\Scripts\python.exe") -m app.migrate_master
& (Join-Path $BackendRoot ".venv\Scripts\python.exe") -m app.migrate_local

if (Test-Path (Join-Path $FlutterRoot "pubspec.yaml")) {
    Write-Host "Projeto Flutter encontrado. Use server-update.ps1 para gerar build web."
}

Write-Host "Instalacao base concluida."
Write-Host "Proximo: rode deploy\windows\server-update.ps1"
