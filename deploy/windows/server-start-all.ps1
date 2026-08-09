$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Lynkar\ERP-PAPEZZOSYNC"
$Cloudflared = "C:\Users\Papezzo_Sync\AppData\Local\Microsoft\WinGet\Packages\Cloudflare.cloudflared_Microsoft.Winget.Source_8wekyb3d8bbwe\cloudflared.exe"
$CloudflaredConfig = "C:\Users\Papezzo_Sync\.cloudflared\config.yml"
$Logs = "C:\Lynkar\logs"

New-Item -ItemType Directory -Force -Path $Logs | Out-Null

powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "deploy\windows\server-start.ps1")

$CloudflaredProcess = Get-Process cloudflared -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $Cloudflared } |
    Select-Object -First 1

if (-not $CloudflaredProcess) {
    Start-Process `
        -FilePath $Cloudflared `
        -ArgumentList "--config", $CloudflaredConfig, "tunnel", "run", "lynkar-erp" `
        -WorkingDirectory $ProjectRoot `
        -RedirectStandardOutput (Join-Path $Logs "cloudflared.out.log") `
        -RedirectStandardError (Join-Path $Logs "cloudflared.err.log") `
        -WindowStyle Hidden
}

Start-Sleep -Seconds 3

Get-NetTCPConnection -LocalPort 5000,5100,5200,8000 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess
