<#
.SYNOPSIS
    Instala o kit completo de integracao Godot + MCP em um projeto.

.DESCRIPTION
    Orquestra: servidor MCP (clone/atualizacao + npm ci + build), addon
    godot_ai_bridge, [editor_plugins] no project.godot, skill godot-live,
    scripts de apoio, bloco no AGENTS.md e opencode.json. Preserva o que ja
    existe: faz backup do que altera e mescla o opencode.json em vez de
    sobrescrever. Termina rodando o diagnostico (tools/doctor.ps1).

.PARAMETER ProjectPath
    Raiz do projeto Godot (onde esta o project.godot). Padrao: diretorio atual.

.PARAMETER InstallDir
    Onde o servidor MCP fica. Padrao: ~/Tools/godot-mcp

.PARAMETER SkipUpdate
    Nao busca atualizacoes do servidor MCP.

.PARAMETER SkipDoctor
    Nao roda o diagnostico ao final.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/install.ps1 -ProjectPath "C:\meu-jogo"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$InstallDir = (Join-Path $HOME 'Tools\godot-mcp'),
    [switch]$SkipUpdate,
    [switch]$SkipDoctor
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot

function Write-Step {
    param([string]$Message)
    Write-Host "[kit] $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string]$Message)
    Write-Host "[kit] $Message" -ForegroundColor Yellow
}

# UTF-8 sem BOM: BOM quebra o parser JSON do opencode.json.
function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Backup-Path {
    param([string]$Path, [string]$Root)
    if (-not (Test-Path $Path)) { return }
    $dir = Join-Path $Root '.kit-backup'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $leaf = Split-Path $Path -Leaf
    $dest = Join-Path $dir ("{0}.{1}.bak" -f $leaf, $stamp)
    Copy-Item -Recurse -Force $Path $dest
    Write-Note "backup: $dest"
}

function Test-DirEqual {
    param([string]$Left, [string]$Right)
    if (-not (Test-Path $Left) -or -not (Test-Path $Right)) { return $false }
    $leftFiles = Get-ChildItem $Left -Recurse -File
    $rightFiles = Get-ChildItem $Right -Recurse -File
    if ($leftFiles.Count -ne $rightFiles.Count) { return $false }
    foreach ($file in $leftFiles) {
        $rel = $file.FullName.Substring($Left.Length).TrimStart('\', '/')
        $other = Join-Path $Right $rel
        if (-not (Test-Path $other)) { return $false }
        if ((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $other).Hash) { return $false }
    }
    return $true
}

if (-not (Test-Path (Join-Path $ProjectPath 'project.godot'))) {
    throw "Nao ha project.godot em: $ProjectPath"
}

# 1. servidor (clone/update) + dependencias + build + addon + [editor_plugins]
$setupArgs = @{ ProjectPath = $ProjectPath; InstallDir = $InstallDir }
if ($SkipUpdate) { $setupArgs['SkipUpdate'] = $true }
& (Join-Path $PSScriptRoot 'setup-godot-mcp.ps1') @setupArgs

# 2. skill (atualiza se mudou; guarda a versao anterior)
$skillSource = Join-Path $kitRoot '.opencode\skills\godot-live'
if (-not (Test-Path $skillSource)) {
    throw "Skill nao encontrada: $skillSource"
}
$skillsDir = Join-Path $ProjectPath '.opencode\skills'
$skillTarget = Join-Path $skillsDir 'godot-live'
if (Test-DirEqual $skillSource $skillTarget) {
    Write-Step 'Skill godot-live ja esta atualizada'
}
else {
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    if (Test-Path $skillTarget) { Backup-Path -Path $skillTarget -Root $ProjectPath }
    Copy-Item -Recurse -Force $skillSource $skillsDir
    Write-Step 'Skill godot-live instalada em .opencode/skills/'
}

# 3. scripts de apoio dentro do projeto (o AGENTS.md aponta para eles)
$toolsDir = Join-Path $ProjectPath 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
foreach ($script in @('setup-godot-mcp.ps1', 'dump-godot-api.ps1', 'doctor.ps1')) {
    Copy-Item -Force (Join-Path $PSScriptRoot $script) $toolsDir
}
Write-Step 'Scripts copiados para tools/'

# 4. AGENTS.md (acrescenta o bloco; nunca reescreve o arquivo)
$agentsFile = Join-Path $ProjectPath 'AGENTS.md'
$marker = '## Ferramentas de desenvolvimento'
$block = @'

## Ferramentas de desenvolvimento
- Integracao ao vivo com o editor: carregue a skill **`godot-live`** antes de usar ferramentas `godot_*`.
- Diagnosticar a instalacao: `powershell -ExecutionPolicy Bypass -File tools/doctor.ps1`
- Reinstalar/atualizar a ponte: `powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1`
- Referencia de API da engine: `%LOCALAPPDATA%\godot-api\<versao>` (regenere com `tools/dump-godot-api.ps1`).
- `opencode.json` usa o formato V2: servidores em `mcp.servers`.
'@
if (-not (Test-Path $agentsFile)) {
    Write-TextNoBom -Path $agentsFile -Text $block.TrimStart()
    Write-Step 'AGENTS.md criado com o bloco de ferramentas'
}
elseif (-not (Select-String -Path $agentsFile -Pattern $marker -SimpleMatch -Quiet)) {
    Backup-Path -Path $agentsFile -Root $ProjectPath
    $current = Get-Content $agentsFile -Raw
    Write-TextNoBom -Path $agentsFile -Text ($current.TrimEnd() + "`n" + $block)
    Write-Step 'Bloco de ferramentas adicionado ao AGENTS.md'
}
else {
    Write-Step 'AGENTS.md ja possui o bloco de ferramentas'
}

# 5. opencode.json: cria se faltar, senao mescla mantendo os servidores existentes
$configFile = Join-Path $ProjectPath 'opencode.json'
$serverJs = (Join-Path $InstallDir 'dist\index.js').Replace('\', '/')

function New-GodotServerEntry {
    param([string]$ServerPath)
    return [pscustomobject]@{
        type    = 'local'
        command = @('node', $ServerPath)
        cwd     = '.'
    }
}

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
    $config = $null
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { }
    if ($null -eq $config -or $config -is [array] -or $config -is [string]) {
        Write-Note 'opencode.json nao e JSON puro (talvez tenha comentarios). Nao alterei o arquivo.'
        Write-Note 'Adicione manualmente, dentro de "mcp": { "servers": { ... } }:'
        Write-Host '  "godot": { "type": "local", "command": ["node", "' -NoNewline
        Write-Host $serverJs -NoNewline
        Write-Host '"], "cwd": "." }'
    }
    else {
        if (-not ($config.PSObject.Properties.Name -contains 'mcp')) {
            $config | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{ servers = [pscustomobject]@{} })
        }
        if (-not ($config.mcp.PSObject.Properties.Name -contains 'servers')) {
            $config.mcp | Add-Member -NotePropertyName servers -NotePropertyValue ([pscustomobject]@{})
        }

        if ($config.mcp.servers.PSObject.Properties.Name -contains 'godot') {
            $current = @($config.mcp.servers.godot.command)
            if ($current.Count -ge 2 -and $current[1] -eq $serverJs) {
                Write-Step 'opencode.json ja aponta para este servidor (nada alterado)'
            }
            else {
                Write-Note "opencode.json ja tem mcp.servers.godot apontando para '$($current -join ' ')' - mantido como esta."
            }
        }
        else {
            $servers = [pscustomobject]@{}
            foreach ($property in $config.mcp.servers.PSObject.Properties) {
                $servers | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            }
            $servers | Add-Member -NotePropertyName 'godot' -NotePropertyValue (New-GodotServerEntry -ServerPath $serverJs)
            $config.mcp | Add-Member -NotePropertyName servers -NotePropertyValue $servers -Force
            Backup-Path -Path $configFile -Root $ProjectPath
            Write-TextNoBom -Path $configFile -Text ($config | ConvertTo-Json -Depth 32)
            Write-Step 'mcp.servers.godot adicionado ao opencode.json existente (demais servidores preservados)'
        }
    }
}

Write-Host ''
Write-Step 'Instalacao concluida.'
Write-Host '  1. Abra o projeto no Godot (a ponte sobe em ws://127.0.0.1:6550)'
Write-Host '  2. Abra o OpenCode na pasta do projeto'
Write-Host '  3. Peca: "conecte ao Godot"'

# 6. diagnostico
if (-not $SkipDoctor) {
    $doctor = Join-Path $PSScriptRoot 'doctor.ps1'
    if (Test-Path $doctor) {
        Write-Host ''
        Write-Step 'Diagnostico'
        & $doctor -ProjectPath $ProjectPath -InstallDir $InstallDir
        exit $LASTEXITCODE
    }
}
