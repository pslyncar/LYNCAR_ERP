$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Lynkar\ERP-PAPEZZOSYNC"
$BackendRoot = Join-Path $ProjectRoot "backend"
$WebRoot = Join-Path $ProjectRoot "admin_app\admin_flutter\build\web"
$PublicSiteRoot = "C:\Lynkar\SITE-LYNCAR-COM-BR\build\web"
$UpdatesRoot = "C:\Lynkar\updates"
$Python = Join-Path $BackendRoot ".venv\Scripts\python.exe"
$Logs = "C:\Lynkar\logs"

New-Item -ItemType Directory -Force -Path $Logs | Out-Null

foreach ($port in @(5000, 5100, 5200, 8000)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
}

Start-Process `
    -FilePath $Python `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000" `
    -WorkingDirectory $BackendRoot `
    -RedirectStandardOutput (Join-Path $Logs "api.out.log") `
    -RedirectStandardError (Join-Path $Logs "api.err.log") `
    -WindowStyle Hidden

if (Test-Path (Join-Path $WebRoot "index.html")) {
    Start-Process `
        -FilePath $Python `
        -ArgumentList `
            (Join-Path $ProjectRoot "deploy\windows\spa_server.py"), `
            "--port", "5000", "--bind", "0.0.0.0" `
        -WorkingDirectory $WebRoot `
        -RedirectStandardOutput (Join-Path $Logs "web.out.log") `
        -RedirectStandardError (Join-Path $Logs "web.err.log") `
        -WindowStyle Hidden
} else {
    Write-Host "Build web nao encontrado em $WebRoot. Instale Flutter e rode server-update.ps1 para gerar."
}

if (Test-Path (Join-Path $PublicSiteRoot "index.html")) {
    Start-Process `
        -FilePath $Python `
        -ArgumentList "-m", "http.server", "5100", "--bind", "0.0.0.0" `
        -WorkingDirectory $PublicSiteRoot `
        -RedirectStandardOutput (Join-Path $Logs "site-publico.out.log") `
        -RedirectStandardError (Join-Path $Logs "site-publico.err.log") `
        -WindowStyle Hidden
} else {
    Write-Host "Site publico nao encontrado em $PublicSiteRoot."
}

if (Test-Path (Join-Path $UpdatesRoot "pdv\windows")) {
    Start-Process `
        -FilePath $Python `
        -ArgumentList "-m", "http.server", "5200", "--bind", "0.0.0.0" `
        -WorkingDirectory $UpdatesRoot `
        -RedirectStandardOutput (Join-Path $Logs "updates.out.log") `
        -RedirectStandardError (Join-Path $Logs "updates.err.log") `
        -WindowStyle Hidden
} else {
    Write-Host "Pasta de updates nao encontrada em $UpdatesRoot."
}

Start-Sleep -Seconds 3

Write-Host "Lynkar rodando:"
if (Test-Path (Join-Path $WebRoot "index.html")) {
    Write-Host "Web local: http://127.0.0.1:5000"
}
if (Test-Path (Join-Path $PublicSiteRoot "index.html")) {
    Write-Host "Site publico local: http://127.0.0.1:5100"
}
if (Test-Path (Join-Path $UpdatesRoot "pdv\windows")) {
    Write-Host "Updates local: http://127.0.0.1:5200"
}
Write-Host "API local: http://127.0.0.1:8000/docs"
Get-NetTCPConnection -LocalPort 5000,5100,5200,8000 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess
