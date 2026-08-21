param(
    [Parameter(Mandatory = $true)]
    [string]$WebRoot
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $WebRoot)) {
    throw "Build web nao encontrado: $WebRoot"
}

$Version = Get-Date -Format "yyyyMMddHHmmss"
$IndexPath = Join-Path $WebRoot "index.html"
$BootstrapPath = Join-Path $WebRoot "flutter_bootstrap.js"
$MainPath = Join-Path $WebRoot "main.dart.js"

if (-not (Test-Path $IndexPath)) {
    throw "index.html nao encontrado em $WebRoot"
}
if (-not (Test-Path $BootstrapPath)) {
    throw "flutter_bootstrap.js nao encontrado em $WebRoot"
}
if (-not (Test-Path $MainPath)) {
    throw "main.dart.js nao encontrado em $WebRoot"
}

$VersionedBootstrapName = "flutter_bootstrap.$Version.js"
$VersionedMainName = "main.$Version.dart.js"
$VersionedBootstrapPath = Join-Path $WebRoot $VersionedBootstrapName
$VersionedMainPath = Join-Path $WebRoot $VersionedMainName

Copy-Item -LiteralPath $BootstrapPath -Destination $VersionedBootstrapPath -Force
Copy-Item -LiteralPath $MainPath -Destination $VersionedMainPath -Force

$IndexHtml = Get-Content -LiteralPath $IndexPath -Raw
$IndexHtml = $IndexHtml -replace 'flutter_bootstrap(?:\.\d+)?\.js', $VersionedBootstrapName
Set-Content -LiteralPath $IndexPath -Value $IndexHtml -Encoding UTF8

$Bootstrap = Get-Content -LiteralPath $VersionedBootstrapPath -Raw
$Bootstrap = $Bootstrap -replace 'main(?:\.\d+)?\.dart\.js', $VersionedMainName
Set-Content -LiteralPath $VersionedBootstrapPath -Value $Bootstrap -Encoding UTF8

$ManifestPath = Join-Path $WebRoot "version.json"
@{
    version = $Version
    flutter_bootstrap = $VersionedBootstrapName
    main = $VersionedMainName
    generated_at = (Get-Date).ToString("s")
} | ConvertTo-Json | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

$FontManifestPath = Join-Path $WebRoot "assets\FontManifest.json"
$MaterialFontPath = Join-Path $WebRoot "assets\fonts\MaterialIcons-Regular.otf"
if ((Test-Path $FontManifestPath) -and (Test-Path $MaterialFontPath)) {
    $VersionedMaterialFontName = "MaterialIcons-Regular.$Version.otf"
    $VersionedMaterialFontPath = Join-Path $WebRoot "assets\fonts\$VersionedMaterialFontName"
    Copy-Item -LiteralPath $MaterialFontPath -Destination $VersionedMaterialFontPath -Force

    $FontManifest = Get-Content -LiteralPath $FontManifestPath -Raw
    $FontManifest = $FontManifest -replace 'fonts/MaterialIcons-Regular(?:\.\d+)?\.otf', "fonts/$VersionedMaterialFontName"
    Set-Content -LiteralPath $FontManifestPath -Value $FontManifest -Encoding UTF8
}

Write-Host "Cache bust aplicado:"
Write-Host " - $VersionedBootstrapName"
Write-Host " - $VersionedMainName"
if ($VersionedMaterialFontName) {
    Write-Host " - $VersionedMaterialFontName"
}
