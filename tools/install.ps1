<#
.SYNOPSIS
    Instala o kit completo de integracao Godot + MCP em um projeto.

.DESCRIPTION
    Orquestra: servidor MCP (clone + build), addon godot_ai_bridge,
    [editor_plugins] no project.godot, skill godot-live, scripts de apoio,
    bloco no AGENTS.md e opencode.json. Idempotente.

.PARAMETER ProjectPath
    Raiz do projeto Godot (onde esta o project.godot). Padrao: diretorio atual.

.PARAMETER InstallDir
    Onde o servidor MCP sera clonado. Padrao: ~/Tools/godot-mcp

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/install.ps1 -ProjectPath "C:\meu-jogo"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$InstallDir = (Join-Path $HOME 'Tools\godot-mcp')
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot

function Write-Step {
    param([string]$Message)
    Write-Host "[kit] $Message" -ForegroundColor Cyan
}

# UTF-8 sem BOM: BOM quebra o parser JSON do opencode.json.
function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

if (-not (Test-Path (Join-Path $ProjectPath 'project.godot'))) {
    throw "Nao ha project.godot em: $ProjectPath"
}

# 1. servidor + addon + [editor_plugins]
& (Join-Path $PSScriptRoot 'setup-godot-mcp.ps1') -ProjectPath $ProjectPath -InstallDir $InstallDir

# 2. skill
$skillSource = Join-Path $kitRoot '.opencode\skills\godot-live'
if (-not (Test-Path $skillSource)) {
    throw "Skill nao encontrada: $skillSource"
}
$skillsDir = Join-Path $ProjectPath '.opencode\skills'
New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
Copy-Item -Recurse -Force $skillSource $skillsDir
Write-Step 'Skill godot-live instalada em .opencode/skills/'

# 3. scripts de apoio dentro do projeto (o AGENTS.md aponta para eles)
$toolsDir = Join-Path $ProjectPath 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
foreach ($script in @('setup-godot-mcp.ps1', 'dump-godot-api.ps1')) {
    Copy-Item -Force (Join-Path $PSScriptRoot $script) $toolsDir
}
Write-Step 'Scripts copiados para tools/'

# 4. AGENTS.md
$agentsFile = Join-Path $ProjectPath 'AGENTS.md'
$marker = '## Ferramentas de desenvolvimento'
$block = @'

## Ferramentas de desenvolvimento
- Integracao ao vivo com o editor: carregue a skill **`godot-live`** antes de usar ferramentas `godot_*`.
- Reinstalar a ponte: `powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1`
- Referencia de API da engine: `%LOCALAPPDATA%\godot-api\<versao>` (regenere com `tools/dump-godot-api.ps1`).
- `opencode.json` usa o formato V2: servidores em `mcp.servers`.
'@
if (-not (Test-Path $agentsFile)) {
    Write-TextNoBom -Path $agentsFile -Text $block.TrimStart()
    Write-Step 'AGENTS.md criado com o bloco de ferramentas'
}
elseif (-not (Select-String -Path $agentsFile -Pattern $marker -SimpleMatch -Quiet)) {
    $current = Get-Content $agentsFile -Raw
    Write-TextNoBom -Path $agentsFile -Text ($current.TrimEnd() + "`n" + $block)
    Write-Step 'Bloco de ferramentas adicionado ao AGENTS.md'
}
else {
    Write-Step 'AGENTS.md ja possui o bloco de ferramentas'
}

# 5. opencode.json
$configFile = Join-Path $ProjectPath 'opencode.json'
$serverJs = (Join-Path $InstallDir 'dist\index.js').Replace('\', '/')
if (-not (Test-Path $configFile)) {
    $json = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "godot": {
        "type": "local",
        "command": ["node", "$serverJs"],
        "cwd": "."
      }
    }
  }
}
"@
    Write-TextNoBom -Path $configFile -Text $json
    Write-Step 'opencode.json criado'
}
else {
    Write-Step 'opencode.json ja existe: compare com opencode.example.jsonc e ajuste a mao'
}

Write-Host ''
Write-Step 'Instalacao concluida.'
Write-Host '  1. Abra o projeto no Godot (a ponte sobe em ws://127.0.0.1:6550)'
Write-Host '  2. Abra o OpenCode na pasta do projeto'
Write-Host '  3. Peca: "conecte ao Godot"'
