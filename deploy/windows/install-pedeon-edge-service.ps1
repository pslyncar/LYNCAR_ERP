param(
    [string]$ProjectRoot = "C:\erp_lyncar_pedeon_work",
    [string]$CloudUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ProjectRoot `"$ProjectRoot`" -CloudUrl `"$CloudUrl`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
    exit 0
}

$EdgeRoot = Join-Path $ProjectRoot "edge_service"
$DataRoot = Join-Path $env:ProgramData "Lyncar\Edge"
$VenvRoot = Join-Path $DataRoot "venv"
$Python = Join-Path $VenvRoot "Scripts\python.exe"
$Pip = Join-Path $VenvRoot "Scripts\pip.exe"

if (-not (Test-Path $EdgeRoot)) { throw "Edge nao encontrado em $EdgeRoot" }
New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
icacls.exe $DataRoot /inheritance:r /grant:r "SYSTEM:(OI)(CI)(F)" "Administrators:(OI)(CI)(F)" | Out-Null
if (-not (Test-Path $Python)) { py -3 -m venv $VenvRoot }
& $Pip install --upgrade pip
& $Pip install -r (Join-Path $EdgeRoot "requirements.txt")

$env:LYNCAR_EDGE_CLOUD_URL = $CloudUrl
$env:LYNCAR_EDGE_DATA_DIR = $DataRoot
$env:PYTHONPATH = $EdgeRoot
[Environment]::SetEnvironmentVariable("LYNCAR_EDGE_CLOUD_URL", $CloudUrl, "Machine")
[Environment]::SetEnvironmentVariable("LYNCAR_EDGE_DATA_DIR", $DataRoot, "Machine")

$serviceScript = Join-Path $EdgeRoot "lyncar_edge\windows_service.py"
$existing = Get-Service -Name "LyncarEdge" -ErrorAction SilentlyContinue
if ($existing) {
    Stop-Service -Name "LyncarEdge" -Force -ErrorAction SilentlyContinue
    & $Python $serviceScript remove
}
& $Python $serviceScript --startup auto install
& sc.exe config LyncarEdge obj= LocalSystem
& sc.exe failure LyncarEdge reset= 86400 actions= restart/5000/restart/15000/restart/60000
& $Python $serviceScript start
Write-Host "Lyncar Edge instalado e iniciado em http://127.0.0.1:8765"
Write-Host "Abra o PedeOn e faça o primeiro login; a configuracao sera criada automaticamente."
