param(
    [string]$InstallPath = "$env:ProgramData\PapezzoSync\Agent",
    [string]$TaskName = "PapezzoSync Agent"
)

$ErrorActionPreference = "Stop"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path $InstallPath) {
    Remove-Item -LiteralPath $InstallPath -Recurse -Force
}

Write-Host "Agente removido."
