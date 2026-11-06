<#
.SYNOPSIS
    Instala o servidor MCP do Godot e o addon godot_ai_bridge em um projeto.

.DESCRIPTION
    Clona o servidor (alexmeckes/godot-mcp), compila, copia o addon e
    registra o plugin em [editor_plugins] do project.godot.
    Idempotente: pode rodar quantas vezes quiser.

.PARAMETER ProjectPath
    Raiz do projeto Godot. Padrao: diretorio atual.

.PARAMETER InstallDir
    Onde o servidor sera clonado. Padrao: ~/Tools/godot-mcp

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1 -ProjectPath "C:\meu-jogo"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$InstallDir = (Join-Path $HOME 'Tools\godot-mcp'),
    [string]$RepoUrl = 'https://github.com/alexmeckes/godot-mcp'
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[godot-mcp] $Message" -ForegroundColor Cyan
}

# Grava texto em UTF-8 sem BOM (Set-Content -Encoding UTF8 poe BOM no PS 5.1,
# e BOM quebra o parser JSON do opencode.json).
function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

# Executa um comando externo e trata o stderr como texto, nao como erro do
# PowerShell (npm e git escrevem avisos em stderr e isso derrubaria o script).
function Invoke-External {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe $($Arguments -join ' ') falhou (exit $LASTEXITCODE)"
    }
}

$projectFile = Join-Path $ProjectPath 'project.godot'
if (-not (Test-Path $projectFile)) {
    throw "Projeto Godot nao encontrado: $projectFile"
}

if (-not (Test-Path $InstallDir)) {
    Write-Step "Clonando $RepoUrl"
    Invoke-External git @('clone', '--depth', '1', $RepoUrl, $InstallDir)
}
else {
    Write-Step "Servidor ja existe em $InstallDir"
}

Push-Location $InstallDir
try {
    if (-not (Test-Path (Join-Path $InstallDir 'node_modules'))) {
        Write-Step 'Instalando dependencias (npm install)'
        Invoke-External npm @('install', '--no-audit', '--no-fund')
    }

    Write-Step 'Compilando servidor (npm run build)'
    Invoke-External npm @('run', 'build')
}
finally {
    Pop-Location
}

$serverJs = Join-Path $InstallDir 'dist\index.js'
if (-not (Test-Path $serverJs)) {
    throw "Build nao gerou $serverJs"
}

$addonSource = Join-Path $InstallDir 'addons\godot_ai_bridge'
if (-not (Test-Path $addonSource)) {
    throw "Addon nao encontrado: $addonSource"
}

$addonsDir = Join-Path $ProjectPath 'addons'
New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
Copy-Item -Recurse -Force $addonSource $addonsDir
Write-Step 'Addon copiado para addons/godot_ai_bridge'

$entry = 'res://addons/godot_ai_bridge/plugin.cfg'
$content = Get-Content $projectFile -Raw
if ($content -match [regex]::Escape($entry)) {
    Write-Step 'Plugin ja registrado em [editor_plugins]'
}
elseif ($content -match '(?ms)^\[editor_plugins\].*?^enabled=PackedStringArray\((.*?)\)') {
    $existing = $Matches[1].Trim().TrimEnd(',')
    $merged = if ($existing) { "$existing, `"$entry`"" } else { "`"$entry`"" }
    $content = $content -replace '(?ms)(^\[editor_plugins\].*?^enabled=PackedStringArray\()(.*?)(\))', "`$1$merged`$3"
    Write-TextNoBom -Path $projectFile -Text $content
    Write-Step 'Plugin adicionado ao [editor_plugins] existente'
}
else {
    $content = $content.TrimEnd() + "`n`n[editor_plugins]`n`nenabled=PackedStringArray(`"$entry`")`n"
    Write-TextNoBom -Path $projectFile -Text $content
    Write-Step 'Secao [editor_plugins] criada'
}

Write-Step 'Pronto. Abra o editor e confirme a ponte em ws://127.0.0.1:6550'
