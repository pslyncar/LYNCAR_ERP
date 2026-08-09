param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [int]$EquipmentId,

    [Parameter(Mandatory = $true)]
    [string]$AgentToken,

    [int]$IntervalSeconds = 10,

    [string]$InstallPath = "$env:ProgramData\PapezzoSync\Agent",

    [string]$TaskName = "PapezzoSync Agent"
)

$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    throw "Python nao encontrado no PATH. Instale o Python 3 e marque a opcao 'Add python.exe to PATH'."
}

New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallPath "logs") -Force | Out-Null

Copy-Item -Path (Join-Path $sourceRoot "papezzosync_agent") -Destination $InstallPath -Recurse -Force
Copy-Item -Path (Join-Path $sourceRoot "requirements.txt") -Destination $InstallPath -Force

$config = [ordered]@{
    api_base_url       = $ApiBaseUrl.TrimEnd("/")
    equipment_id       = $EquipmentId
    agent_token        = $AgentToken
    interval_seconds   = $IntervalSeconds
    collect_logged_user = $false
}

$configPath = Join-Path $InstallPath "config.json"
$config | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

$venvPython = Join-Path $InstallPath ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    & $python.Source -m venv (Join-Path $InstallPath ".venv")
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $InstallPath "requirements.txt")

$runScript = Join-Path $InstallPath "run-agent.ps1"
$stdoutLog = Join-Path $InstallPath "logs\agent.out.log"
$stderrLog = Join-Path $InstallPath "logs\agent.err.log"

@"
`$ErrorActionPreference = "Stop"
Set-Location "$InstallPath"
& "$venvPython" -m papezzosync_agent.main --config "$configPath" *> "$stdoutLog"
"@ | Set-Content -Path $runScript -Encoding UTF8

$taskCreated = $false
try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Agente de monitoramento PapezzoSync" `
        -Force | Out-Null
    $taskCreated = $true
} catch {
    Write-Host ""
    Write-Host "Nao foi possivel criar tarefa agendada. Vou usar a pasta Inicializar do Windows."
    Write-Host "Motivo: $($_.Exception.Message)"

    $startupFolder = [Environment]::GetFolderPath("Startup")
    $startupScript = Join-Path $startupFolder "PapezzoSync Agent.bat"
    @"
@echo off
cd /d "$InstallPath"
start "" /min "$venvPython" -m papezzosync_agent.main --config "$configPath"
"@ | Set-Content -Path $startupScript -Encoding ASCII
}

Write-Host ""
Write-Host "Agente instalado em: $InstallPath"
if ($taskCreated) {
    Write-Host "Tarefa criada: $TaskName"
} else {
    Write-Host "Inicializacao automatica criada na pasta Inicializar do Windows."
}
Write-Host "API: $ApiBaseUrl"
Write-Host "Equipamento: $EquipmentId"
Write-Host ""
Write-Host "Para testar agora:"
Write-Host "cd `"$InstallPath`""
Write-Host ".\.venv\Scripts\python.exe -m papezzosync_agent.main --config config.json --once"
Write-Host ""
Write-Host "Para iniciar em segundo plano agora:"
if ($taskCreated) {
    Write-Host "Start-ScheduledTask -TaskName `"$TaskName`""
} else {
    Write-Host "Start-Process -WindowStyle Hidden -FilePath `"$venvPython`" -ArgumentList '-m','papezzosync_agent.main','--config','`"$configPath`"' -WorkingDirectory `"$InstallPath`""
}
