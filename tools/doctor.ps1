<#
.SYNOPSIS
    Diagnostica a instalacao da integracao Godot + MCP em um projeto.

.DESCRIPTION
    Verifica Node.js, servidor MCP, dependencias, clone git, addon e plugin,
    opencode.json, token de pareamento, porta da ponte e compatibilidade de
    versao entre engine e projeto. Pode rodar com o editor aberto ou fechado:
    o que depende do editor aparece como AVISO, nao como falha.

    Codigo de saida: 0 se nenhum item FALHOU; 1 se houver falha.

.PARAMETER ProjectPath
    Raiz do projeto Godot. Padrao: diretorio atual.

.PARAMETER InstallDir
    Onde o servidor MCP esta instalado. Padrao: ~/Tools/godot-mcp

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/doctor.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$InstallDir = (Join-Path $HOME 'Tools\godot-mcp'),
    [int]$Port = 6550
)

$ErrorActionPreference = 'Continue'
$MinNodeMajor = 20
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Item, [string]$Status, [string]$Detail)
    $checks.Add([pscustomobject]@{ Status = $Status; Item = $Item; Detail = $Detail })
}

function Test-PortOpen {
    param([int]$TargetPort)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $TargetPort)
        if ($task.Wait(700) -and $client.Connected) { return $true }
        return $false
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Find-GodotExe {
    $fromPath = Get-Command 'godot' -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    foreach ($dir in @('C:\Godot', (Join-Path $env:LOCALAPPDATA 'Programs\Godot'))) {
        if (-not (Test-Path $dir)) { continue }
        $found = Get-ChildItem $dir -Filter 'Godot*.exe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

# --- ambiente ---
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Add-Check 'Node.js' 'FALHA' 'node nao encontrado no PATH'
}
else {
    $nodeVersion = (& node -p 'process.versions.node').Trim()
    $major = [int](($nodeVersion -split '\.')[0])
    $status = if ($major -ge $MinNodeMajor) { 'OK' } else { 'FALHA' }
    $detail = "v$nodeVersion (exige >= $MinNodeMajor)"
    if ($status -eq 'FALHA') { $detail += ' - atualize em https://nodejs.org' }
    Add-Check 'Node.js' $status $detail
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if ($npm) { Add-Check 'npm' 'OK' ("v" + (& npm --version).Trim()) }
else { Add-Check 'npm' 'FALHA' 'npm nao encontrado no PATH' }

if (Get-Command git -ErrorAction SilentlyContinue) {
    Add-Check 'git' 'OK' ((& git --version) -replace '^git version ', '')
}
else {
    Add-Check 'git' 'AVISO' 'nao encontrado - necessario apenas para instalar/atualizar'
}

# --- servidor ---
$serverJs = Join-Path $InstallDir 'dist\index.js'
if (Test-Path $serverJs) {
    $serverPkg = Join-Path $InstallDir 'package.json'
    $version = if (Test-Path $serverPkg) { (Get-Content $serverPkg -Raw | ConvertFrom-Json).version } else { '?' }
    $size = [math]::Round((Get-Item $serverJs).Length / 1KB)
    Add-Check 'Servidor MCP' 'OK' "dist/index.js ($size KB), pacote $version"
}
else {
    Add-Check 'Servidor MCP' 'FALHA' "nao encontrado: $serverJs (rode tools/setup-godot-mcp.ps1)"
}

$modules = Join-Path $InstallDir 'node_modules'
if (-not (Test-Path $modules)) {
    Add-Check 'Dependencias' 'FALHA' 'node_modules ausente (rode tools/setup-godot-mcp.ps1)'
}
else {
    $lock = Join-Path $InstallDir 'package-lock.json'
    $stamp = Join-Path $modules '.package-lock.json'
    if ((Test-Path $lock) -and (Test-Path $stamp) -and ((Get-Item $lock).LastWriteTimeUtc -gt (Get-Item $stamp).LastWriteTimeUtc)) {
        Add-Check 'Dependencias' 'AVISO' 'package-lock.json mais novo que node_modules - rode setup-godot-mcp.ps1'
    }
    else {
        Add-Check 'Dependencias' 'OK' 'node_modules coerente com o lockfile'
    }
}

if (Test-Path (Join-Path $InstallDir '.git')) {
    Push-Location $InstallDir
    try {
        $head = (& git rev-parse --short HEAD).Trim()
        $status = & git status --porcelain 2>&1
        # dist/ e saida de build (o upstream a versiona): nao e alteracao do usuario.
        $sourceChanges = @($status | Where-Object { $_ -and $_.ToString().Trim() -and ($_.ToString() -notmatch 'dist[/\\]') })
        $detail = "commit $head"
        if ($sourceChanges.Count -gt 0) { $detail += ' (com alteracoes locais na fonte)' }
        Add-Check 'Clone do servidor' 'OK' $detail
    }
    finally {
        Pop-Location
    }
}
elseif (Test-Path $InstallDir) {
    Add-Check 'Clone do servidor' 'AVISO' 'pasta existe mas nao e clone git - atualizacao automatica indisponivel'
}

# --- projeto ---
$projectFile = Join-Path $ProjectPath 'project.godot'
$projectOk = Test-Path $projectFile
if ($projectOk) {
    Add-Check 'project.godot' 'OK' $projectFile
}
else {
    Add-Check 'project.godot' 'FALHA' "nao encontrado em $ProjectPath"
}

$addonDir = Join-Path $ProjectPath 'addons\godot_ai_bridge'
$required = @('plugin.cfg', 'godot_ai_bridge.gd', 'message_handler.gd', 'runtime_bridge.gd', 'ws_server.gd')
if (-not (Test-Path $addonDir)) {
    Add-Check 'Addon' 'FALHA' 'addons/godot_ai_bridge ausente'
}
else {
    $missing = $required | Where-Object { -not (Test-Path (Join-Path $addonDir $_)) }
    if ($missing) {
        Add-Check 'Addon' 'FALHA' ("faltando: " + ($missing -join ', '))
    }
    else {
        $addonVersion = '?'
        $addonPlugin = Join-Path $addonDir 'plugin.cfg'
        if (Test-Path $addonPlugin) {
            $line = Select-String -Path $addonPlugin -Pattern '^version=' | Select-Object -First 1
            if ($line) { $addonVersion = ($line.Line -split '=', 2)[1].Trim('"') }
        }
        Add-Check 'Addon' 'OK' "$($required.Count) arquivos presentes, versao $addonVersion"
    }
}

if ($projectOk) {
    $content = Get-Content $projectFile -Raw
    if ($content -match [regex]::Escape('res://addons/godot_ai_bridge/plugin.cfg')) {
        Add-Check 'Plugin ativo' 'OK' 'registrado em [editor_plugins]'
    }
    else {
        Add-Check 'Plugin ativo' 'FALHA' '[editor_plugins] nao contem o addon (rode setup-godot-mcp.ps1)'
    }

    $features = if ($content -match '(?m)^config/features=PackedStringArray\(([^)]*)\)') { $Matches[1] } else { '' }
    $projectEngine = if ($features -match '"(\d+\.\d+)"') { $Matches[1] } else { $null }

    $godotExe = Find-GodotExe
    if (-not $godotExe) {
        Add-Check 'Versao da engine' 'AVISO' 'executavel do Godot nao encontrado (PATH ou C:\Godot)'
    }
    else {
        $engineVersion = (& $godotExe --version).Trim()
        $engineShort = (($engineVersion -split '\.')[0..1] -join '.')
        if (-not $projectEngine) {
            Add-Check 'Versao da engine' 'AVISO' "$engineVersion (projeto nao declara config/features)"
        }
        elseif ($engineShort -eq $projectEngine) {
            Add-Check 'Versao da engine' 'OK' "$engineVersion compativel com o projeto ($projectEngine)"
        }
        else {
            Add-Check 'Versao da engine' 'AVISO' "engine $engineVersion vs projeto $projectEngine"
        }

        $apiDir = Join-Path $env:LOCALAPPDATA ("godot-api\" + (($engineVersion -split '\.')[0..2] -join '.'))
        $apiJson = Join-Path $apiDir 'extapi\extension_api.json'
        if (Test-Path $apiJson) {
            Add-Check 'API da engine' 'OK' "snapshot em $apiDir"
        }
        else {
            Add-Check 'API da engine' 'AVISO' "sem snapshot em $apiDir (opcional; gere com tools/dump-godot-api.ps1)"
        }
    }
}

# --- opencode ---
$configFile = Join-Path $ProjectPath 'opencode.json'
if (-not (Test-Path $configFile)) {
    Add-Check 'opencode.json' 'FALHA' 'ausente (rode tools/install.ps1 ou copie opencode.example.jsonc)'
}
else {
    $parsed = $null
    try { $parsed = Get-Content $configFile -Raw | ConvertFrom-Json } catch { }
    if ($null -eq $parsed) {
        Add-Check 'opencode.json' 'FALHA' 'JSON invalido (comentarios nao sao permitidos em .json)'
    }
    else {
        $server = $null
        if ($parsed.PSObject.Properties.Name -contains 'mcp' -and $parsed.mcp.PSObject.Properties.Name -contains 'servers') {
            if ($parsed.mcp.servers.PSObject.Properties.Name -contains 'godot') { $server = $parsed.mcp.servers.godot }
        }
        if (-not $server) {
            Add-Check 'opencode.json' 'FALHA' 'sem mcp.servers.godot (formato V2 usa mcp.servers)'
        }
        else {
            $command = @($server.command)
            $scriptPath = if ($command.Count -ge 2) { $command[1] } else { $null }
            if ($scriptPath -and (Test-Path $scriptPath)) {
                Add-Check 'opencode.json' 'OK' "mcp.servers.godot -> $scriptPath"
            }
            else {
                Add-Check 'opencode.json' 'FALHA' "mcp.servers.godot aponta para caminho inexistente: $scriptPath"
            }
        }
    }
}

# --- runtime (depende do editor aberto) ---
$tokenFile = Join-Path $ProjectPath '.godot\godot-ai-bridge.json'
if (Test-Path $tokenFile) {
    try {
        $token = Get-Content $tokenFile -Raw | ConvertFrom-Json
        if ($null -eq $token) {
            Add-Check 'Token de pareamento' 'AVISO' 'arquivo ilegivel'
        }
        elseif (($token.PSObject.Properties.Name -contains 'token') -and ($token.token -match '^[0-9a-f]{64}$')) {
            Add-Check 'Token de pareamento' 'OK' "porta $($token.port), token de 64 hex"
        }
        else {
            Add-Check 'Token de pareamento' 'AVISO' 'arquivo existe mas sem token valido (plugin nunca inicializou)'
        }
    }
    catch {
        Add-Check 'Token de pareamento' 'AVISO' 'arquivo ilegivel'
    }
}
else {
    Add-Check 'Token de pareamento' 'AVISO' '.godot/godot-ai-bridge.json ausente - abra o editor uma vez'
}

if (Test-PortOpen -TargetPort $Port) {
    Add-Check "Ponte (porta $Port)" 'OK' 'editor escutando em 127.0.0.1'
}
else {
    Add-Check "Ponte (porta $Port)" 'AVISO' 'porta fechada - abra o editor Godot com o plugin ativo'
}

# --- relatorio ---
$checks | Format-Table -AutoSize Status, Item, Detail | Out-String -Width 200 | Write-Host

$fail = @($checks | Where-Object { $_.Status -eq 'FALHA' })
$warn = @($checks | Where-Object { $_.Status -eq 'AVISO' })
$ok = @($checks | Where-Object { $_.Status -eq 'OK' })

Write-Host ("Resumo: {0} OK, {1} aviso(s), {2} falha(s)" -f $ok.Count, $warn.Count, $fail.Count) -ForegroundColor $(if ($fail.Count) { 'Red' } elseif ($warn.Count) { 'Yellow' } else { 'Green' })
if ($fail.Count) {
    Write-Host 'Corrija as falhas acima antes de usar a integracao.' -ForegroundColor Red
    exit 1
}
exit 0
