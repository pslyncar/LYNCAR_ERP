param(
    [string]$ProjectRoot = "C:\erp_lyncar_pedeon_work",
    [string]$CloudUrl = "http://127.0.0.1:8000",
    [string]$PedeOnExe = ""
)

$ErrorActionPreference = "Stop"
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProjectRoot `"$ProjectRoot`" -CloudUrl `"$CloudUrl`" -PedeOnExe `"$PedeOnExe`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
    exit 0
}
$EdgeInstaller = Join-Path $ProjectRoot "deploy\windows\install-pedeon-edge-service.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EdgeInstaller `
    -ProjectRoot $ProjectRoot -CloudUrl $CloudUrl

if ([string]::IsNullOrWhiteSpace($PedeOnExe)) {
    $PedeOnExe = Join-Path $ProjectRoot "pedeon_operations_flutter\build\windows\x64\runner\Release\pedeon_operations.exe"
}
if (-not (Test-Path $PedeOnExe)) {
    Write-Warning "Executavel PedeOn nao encontrado em $PedeOnExe. O Edge foi instalado; gere o build e execute este script novamente."
    exit 0
}

$taskName = "Lyncar PedeOn"
$action = New-ScheduledTaskAction -Execute $PedeOnExe
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "PedeOn configurado para iniciar automaticamente em tela cheia junto com o Windows."
