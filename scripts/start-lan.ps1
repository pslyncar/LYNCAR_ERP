$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$backendPython = Join-Path $root "backend\.venv\Scripts\python.exe"
$webRoot = Join-Path $root "admin_app\admin_flutter\build\web"
$backendRoot = Join-Path $root "backend"

$ipAddress = (
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -like "192.168.*" -and
            $_.PrefixOrigin -ne "WellKnown"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
)

if (-not $ipAddress) {
    $ipAddress = (
        Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*"
            } |
            Select-Object -First 1 -ExpandProperty IPAddress
    )
}

if (-not $ipAddress) {
    throw "Nao foi possivel encontrar o IP local da maquina."
}

foreach ($port in @(5000, 8000)) {
    Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.OwningProcess -and $_.OwningProcess -ne $PID) {
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
}

Start-Process `
    -FilePath $backendPython `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000" `
    -WorkingDirectory $backendRoot `
    -RedirectStandardOutput (Join-Path $backendRoot "backend.lan.out.log") `
    -RedirectStandardError (Join-Path $backendRoot "backend.lan.err.log") `
    -WindowStyle Hidden

Start-Process `
    -FilePath $backendPython `
    -ArgumentList (Join-Path $root "deploy\windows\spa_server.py"), "--port", "5000", "--bind", "0.0.0.0" `
    -WorkingDirectory $webRoot `
    -RedirectStandardOutput (Join-Path $root "admin_app\admin_flutter\web.lan.out.log") `
    -RedirectStandardError (Join-Path $root "admin_app\admin_flutter\web.lan.err.log") `
    -WindowStyle Hidden

Start-Sleep -Seconds 3

Write-Host ""
Write-Host "PapezzoSync rodando na rede local:"
Write-Host "Admin: http://$ipAddress`:5000"
Write-Host "API:   http://$ipAddress`:8000/docs"
Write-Host ""
Write-Host "Agente em outro PC deve usar:"
Write-Host "api_base_url = http://$ipAddress`:8000"
Write-Host ""
Write-Host "Se outro aparelho nao abrir, libere no Firewall do Windows as portas TCP 5000 e 8000 na rede privada."
