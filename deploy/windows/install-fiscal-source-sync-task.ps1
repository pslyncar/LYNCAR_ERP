$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BackendRoot = Join-Path $ProjectRoot "backend"
$PythonExe = Join-Path $BackendRoot ".venv\Scripts\python.exe"
$SyncScript = Join-Path $BackendRoot "scripts\sync_fiscal_sources.py"
$LogDir = Join-Path $ProjectRoot "logs"
$LogFile = Join-Path $LogDir "fiscal_sources_sync.log"
$TaskName = "Lyncar Fiscal Sources Sync"

if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Python do backend nao encontrado em $PythonExe. Rode deploy\windows\server-update.ps1 antes."
}

if (-not (Test-Path -LiteralPath $SyncScript)) {
    throw "Script de sincronizacao fiscal nao encontrado em $SyncScript."
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Command = "`$env:FISCAL_SYNC_LOG_FILE = '$LogFile'; & '$PythonExe' '$SyncScript' --strict --retry-until-success --max-retry-hours 23"

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`"" `
    -WorkingDirectory $BackendRoot

$Trigger = New-ScheduledTaskTrigger -Daily -At 3:15am

$Settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 24)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Sincroniza NCM, CFOP, CEST e IBS/CBS oficiais usados pelo assistente fiscal do Lyncar." `
    -Force | Out-Null

Write-Host "Tarefa agendada criada/atualizada: $TaskName"
Write-Host "Horario: diariamente as 03:15"
Write-Host "Log sugerido: $LogFile"
