$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Lynkar\ERP-PAPEZZOSYNC"
$BackendRoot = Join-Path $ProjectRoot "backend"
$FlutterRoot = Join-Path $ProjectRoot "admin_app\admin_flutter"
$FlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$FlutterBin = if ($FlutterCommand) { $FlutterCommand.Source } else { "C:\DevTools\flutter\bin\flutter.bat" }

Write-Host "Atualizando dependencias do backend..."
& (Join-Path $BackendRoot ".venv\Scripts\pip.exe") install -r (Join-Path $BackendRoot "requirements.txt")

Write-Host "Aplicando migracoes..."
Push-Location $BackendRoot
try {
    & (Join-Path $BackendRoot ".venv\Scripts\python.exe") -m app.migrate_master
    & (Join-Path $BackendRoot ".venv\Scripts\python.exe") -m app.migrate_local
} finally {
    Pop-Location
}

if (Test-Path $FlutterBin) {
    Write-Host "Gerando build web Flutter..."
    Push-Location $FlutterRoot
    & $FlutterBin build web --no-web-resources-cdn --no-tree-shake-icons --no-wasm-dry-run
    Pop-Location

    Write-Host "Versionando assets web para evitar cache..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $ProjectRoot "deploy\windows\cache-bust-flutter-web.ps1") `
        -WebRoot (Join-Path $FlutterRoot "build\web")
} else {
    Write-Host "Flutter nao encontrado em $FlutterBin. Ajuste o caminho neste script."
}

Write-Host "Atualizacao concluida. Rode server-start.ps1 para reiniciar."
