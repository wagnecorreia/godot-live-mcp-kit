<#
.SYNOPSIS
    Gera a referencia de API da engine Godot instalada.

.DESCRIPTION
    Usa o proprio binario para extrair a verdade de terreno: XML de todas as
    classes (--doctool) e o extension_api.json com documentacao
    (--dump-extension-api-with-docs). O destino padrao fica fora do projeto
    (%LOCALAPPDATA%\godot-api\<versao>) para nao inflar o repositorio.

.PARAMETER GodotExe
    Caminho do binario (de preferencia o *console*). Se omitido, procura em
    PATH e em C:\Godot.

.PARAMETER OutDir
    Destino. Padrao: %LOCALAPPDATA%\godot-api\<versao>

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/dump-godot-api.ps1
#>
[CmdletBinding()]
param(
    [string]$GodotExe,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

function Find-GodotExe {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Binario nao encontrado: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }

    $fromPath = Get-Command 'godot' -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $candidates = @('C:\Godot', (Join-Path $env:LOCALAPPDATA 'Programs\Godot'))
    foreach ($dir in $candidates) {
        if (-not (Test-Path $dir)) { continue }
        $console = Get-ChildItem $dir -Filter '*console*.exe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($console) { return $console.FullName }
        $any = Get-ChildItem $dir -Filter 'Godot*.exe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($any) { return $any.FullName }
    }

    throw 'Godot nao encontrado. Use -GodotExe <caminho do executavel>.'
}

$GodotExe = Find-GodotExe -Explicit $GodotExe
$version = (& $GodotExe --version).Trim()
$shortVersion = (($version -split '\.')[0..2] -join '.')

if (-not $OutDir) {
    $OutDir = Join-Path $env:LOCALAPPDATA "godot-api\$shortVersion"
}

$docDir = Join-Path $OutDir 'doc'
$apiDir = Join-Path $OutDir 'extapi'
New-Item -ItemType Directory -Force -Path $docDir, $apiDir | Out-Null

Push-Location $apiDir
try {
    Write-Host "[api] Extraindo classes de $version" -ForegroundColor Cyan
    & $GodotExe --headless --doctool $docDir | Out-Null

    Write-Host '[api] Extraindo extension_api.json com documentacao' -ForegroundColor Cyan
    & $GodotExe --headless --dump-extension-api-with-docs | Out-Null
}
finally {
    Pop-Location
}

$json = Join-Path $apiDir 'extension_api.json'
$xmlCount = (Get-ChildItem $docDir -Filter *.xml -Recurse -ErrorAction SilentlyContinue).Count
if (-not (Test-Path $json)) { throw 'extension_api.json nao foi gerado' }

Write-Host "[api] versao:  $version"
Write-Host "[api] XML:     $xmlCount arquivos em $docDir"
Write-Host "[api] JSON:    $([math]::Round((Get-Item $json).Length / 1MB, 1)) MB em $json"
