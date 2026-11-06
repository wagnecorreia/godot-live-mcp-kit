<#
.SYNOPSIS
    Instala ou atualiza o servidor MCP do Godot e o addon godot_ai_bridge em um projeto.

.DESCRIPTION
    Garante o servidor (alexmeckes/godot-mcp): clona se faltar, atualiza por
    fast-forward se ja existir e estiver limpo, instala dependencias de forma
    reproduzivel (npm ci) e compila. Copia o addon e registra o plugin em
    [editor_plugins] do project.godot. Faz backup de tudo que altera.
    Idempotente: pode rodar quantas vezes quiser.

.PARAMETER ProjectPath
    Raiz do projeto Godot. Padrao: diretorio atual.

.PARAMETER InstallDir
    Onde o servidor fica. Padrao: ~/Tools/godot-mcp

.PARAMETER SkipUpdate
    Nao busca atualizacoes do servidor, mesmo se o clone estiver limpo.

.PARAMETER KeepAddon
    Nao sobrescreve addons/godot_ai_bridge se ele ja existir no projeto.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1 -ProjectPath "C:\meu-jogo"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$InstallDir = (Join-Path $HOME 'Tools\godot-mcp'),
    [string]$RepoUrl = 'https://github.com/alexmeckes/godot-mcp',
    [switch]$SkipUpdate,
    [switch]$KeepAddon
)

$ErrorActionPreference = 'Stop'
$MinNodeMajor = 20

function Write-Step {
    param([string]$Message)
    Write-Host "[godot-mcp] $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string]$Message)
    Write-Host "[godot-mcp] $Message" -ForegroundColor Yellow
}

# Grava texto em UTF-8 sem BOM (Set-Content -Encoding UTF8 poe BOM no PS 5.1,
# e BOM quebra o parser JSON do opencode.json).
function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

# Executa um comando externo sem deixar que o stderr (avisos de npm/git)
# vire erro terminante do PowerShell. Quem decide o sucesso e o exit code.
function Invoke-External {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
            if ($line) { Write-Host "  $line" }
        }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "$Exe $($Arguments -join ' ') falhou (exit $code)"
    }
    return $code
}

# Captura a saida de um comando externo como texto, mesmo quando ele escreve
# em stderr (git emite avisos de fim de linha, por exemplo).
function Get-ExternalOutput {
    param([string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return @($output | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
        })
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

# Compara duas pastas por caminho relativo + SHA256 de cada arquivo.
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

function Assert-Node {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        throw 'Node.js nao encontrado no PATH. Instale Node.js 20 ou superior (https://nodejs.org) e abra um novo terminal.'
    }
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw 'npm nao encontrado no PATH. Reinstale o Node.js (o npm vem junto).'
    }
    $raw = (& node -p 'process.versions.node').Trim()
    $major = [int](($raw -split '\.')[0])
    if ($major -lt $MinNodeMajor) {
        throw "Node.js $raw encontrado, mas o servidor exige $MinNodeMajor ou superior. Atualize em https://nodejs.org."
    }
    $npmVersion = (& npm --version).Trim()
    Write-Step "Node.js $raw / npm $npmVersion"
}

function Assert-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git nao encontrado no PATH. Instale o Git (https://git-scm.com) para baixar o servidor.'
    }
}

# Clona na primeira vez; depois so atualiza por fast-forward quando o clone
# esta limpo. Nunca descarta alteracoes locais.
function Sync-Server {
    if (-not (Test-Path $InstallDir)) {
        Assert-Git
        Write-Step "Clonando $RepoUrl"
        Invoke-External git @('clone', '--depth', '1', $RepoUrl, $InstallDir) | Out-Null
        return
    }

    if (-not (Test-Path (Join-Path $InstallDir '.git'))) {
        Write-Note "$InstallDir existe mas nao e um clone git. Usando como esta (remova a pasta para reinstalar limpo)."
        return
    }

    if ($SkipUpdate) {
        Write-Step 'Atualizacao do servidor ignorada (-SkipUpdate)'
        return
    }

    Push-Location $InstallDir
    try {
        $status = Get-ExternalOutput git @('status', '--porcelain')

        $changed = @($status | Where-Object { $_ -and $_.ToString().Trim() })
        # O upstream versiona dist/ (build). Ele sempre aparece modificado
        # depois de compilar, entao nao conta como alteracao do usuario.
        $sourceChanges = @($changed | Where-Object { $_.ToString() -notmatch 'dist[/\\]' })
        $buildChanges = @($changed | Where-Object { $_.ToString() -match 'dist[/\\]' })

        if ($sourceChanges.Count -gt 0) {
            Write-Note "Ha alteracoes locais em $InstallDir. Atualizacao ignorada para nao sobrescrever nada:"
            $sourceChanges | ForEach-Object { Write-Note "  $_" }
            return
        }

        if ($buildChanges.Count -gt 0) {
            $restore = Invoke-External git @('checkout', '--', 'dist') -AllowFailure
            if ($restore -eq 0) {
                Write-Step 'Build anterior descartado para permitir a atualizacao (sera recompilado)'
            }
        }


        $before = (Get-ExternalOutput git @('rev-parse', '--short', 'HEAD') | Select-Object -First 1).Trim()
        $pull = Invoke-External git @('pull', '--ff-only', '--quiet') -AllowFailure
        if ($pull -ne 0) {
            Write-Note "git pull falhou (conflito, sem upstream ou sem rede). Mantendo $before."
            return
        }
        $after = (Get-ExternalOutput git @('rev-parse', '--short', 'HEAD') | Select-Object -First 1).Trim()
        if ($before -eq $after) {
            Write-Step "Servidor ja esta atualizado ($after)"
        }
        else {
            Write-Step "Servidor atualizado: $before -> $after"
        }
    }
    finally {
        Pop-Location
    }
}

# npm ci quando o lockfile mudou em relacao ao node_modules instalado;
# npm install so como fallback quando nao existe lockfile.
function Install-Dependencies {
    $lock = Join-Path $InstallDir 'package-lock.json'
    $stamp = Join-Path $InstallDir 'node_modules\.package-lock.json'
    $needed = $true
    if (Test-Path $stamp) {
        $needed = (Test-Path $lock) -and ((Get-Item $lock).LastWriteTimeUtc -gt (Get-Item $stamp).LastWriteTimeUtc)
    }

    if (-not $needed) {
        Write-Step 'Dependencias ja compativeis com o package-lock.json'
        return
    }

    if (Test-Path $lock) {
        Write-Step 'Instalando dependencias (npm ci)'
        Invoke-External npm @('ci', '--no-audit', '--no-fund') | Out-Null
    }
    else {
        Write-Step 'Instalando dependencias (npm install, sem lockfile)'
        Invoke-External npm @('install', '--no-audit', '--no-fund') | Out-Null
    }
}

$projectFile = Join-Path $ProjectPath 'project.godot'
if (-not (Test-Path $projectFile)) {
    throw "Projeto Godot nao encontrado: $projectFile"
}

Assert-Node
Sync-Server

Push-Location $InstallDir
try {
    Install-Dependencies
    Write-Step 'Compilando servidor (npm run build)'
    Invoke-External npm @('run', 'build') | Out-Null
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
$addonTarget = Join-Path $addonsDir 'godot_ai_bridge'

if (Test-DirEqual $addonSource $addonTarget) {
    Write-Step 'Addon ja esta na versao do servidor'
}
elseif ($KeepAddon -and (Test-Path $addonTarget)) {
    Write-Note 'Addon do projeto preservado (-KeepAddon)'
}
else {
    if (Test-Path $addonTarget) { Backup-Path -Path $addonTarget -Root $ProjectPath }
    Copy-Item -Recurse -Force $addonSource $addonsDir
    Write-Step 'Addon copiado para addons/godot_ai_bridge'
}

$entry = 'res://addons/godot_ai_bridge/plugin.cfg'
$content = Get-Content $projectFile -Raw
if ($content -match [regex]::Escape($entry)) {
    Write-Step 'Plugin ja registrado em [editor_plugins]'
}
elseif ($content -match '(?ms)^\[editor_plugins\].*?^enabled=PackedStringArray\((.*?)\)') {
    $existing = $Matches[1].Trim().TrimEnd(',')
    $merged = if ($existing) { "$existing, `"$entry`"" } else { "`"$entry`"" }
    $updated = $content -replace '(?ms)(^\[editor_plugins\].*?^enabled=PackedStringArray\()(.*?)(\))', "`$1$merged`$3"
    Backup-Path -Path $projectFile -Root $ProjectPath
    Write-TextNoBom -Path $projectFile -Text $updated
    Write-Step 'Plugin adicionado ao [editor_plugins] existente'
}
else {
    $updated = $content.TrimEnd() + "`n`n[editor_plugins]`n`nenabled=PackedStringArray(`"$entry`")`n"
    Backup-Path -Path $projectFile -Root $ProjectPath
    Write-TextNoBom -Path $projectFile -Text $updated
    Write-Step 'Secao [editor_plugins] criada'
}

Write-Step 'Pronto. Abra o editor e confirme a ponte em ws://127.0.0.1:6550'
