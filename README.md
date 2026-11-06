# Godot Live MCP Kit

Integração ao vivo entre **OpenCode** (ou qualquer cliente MCP) e o **editor Godot 4**.
Um agente de IA consegue abrir cenas, inspecionar a árvore de nós, rodar o jogo, simular
input, ler erros e tirar screenshot — em vez de só editar arquivos no escuro.

```
┌──────────────┐   stdio    ┌──────────────┐   WebSocket 6550   ┌──────────────────┐
│  OpenCode    │───────────▶│  godot-mcp   │───────────────────▶│  Godot Editor    │
│  (agente)    │  JSON-RPC  │  (Node.js)   │      JSON-RPC      │  + AI Bridge     │
└──────────────┘            └──────────────┘                    └──────────────────┘
```

## O que vem no kit

| Peça | Para quê |
|---|---|
| `tools/install.ps1` | Instala tudo em um projeto Godot: servidor, addon, skill e config |
| `tools/setup-godot-mcp.ps1` | Só a parte servidor + addon + `[editor_plugins]` |
| `tools/dump-godot-api.ps1` | Extrai a referência da API do **seu** binário Godot (XML + JSON) |
| `.opencode/skills/godot-live/` | Skill com o procedimento: conectar, diagnosticar, validar, peculiaridades |
| `opencode.example.jsonc` | Configuração MCP no formato **V2** (`mcp.servers`) |
| `AGENTS-snippet.md` | Bloco para colar no `AGENTS.md` do projeto |

O servidor usado é o [alexmeckes/godot-mcp](https://github.com/alexmeckes/godot-mcp) (MIT).
O kit **não redistribui** o addon: ele baixa e compila na sua máquina.

## Requisitos

- **Godot 4.x** — testado em `4.7.2-stable`
- **Node.js 20+**
- **OpenCode V2** (funciona com qualquer cliente MCP que suporte servidores `stdio`)
- Windows + PowerShell para os scripts (os passos manuais funcionam em qualquer OS)

## Instalação

```powershell
git clone https://github.com/wagnecorreia/godot-live-mcp-kit.git
cd godot-live-mcp-kit
powershell -ExecutionPolicy Bypass -File tools/install.ps1 -ProjectPath "C:\caminho\do\seu-projeto-godot"
```

O instalador é idempotente (pode rodar de novo sem duplicar nada). Ele:

1. clona/atualiza o `godot-mcp` em `~/Tools/godot-mcp` (ou em `-InstallDir`) e roda `npm install && npm run build`;
2. copia `addons/godot_ai_bridge` para o seu projeto;
3. registra o plugin em `[editor_plugins]` do `project.godot`, preservando plugins que já estejam lá;
4. copia a skill `godot-live` para `.opencode/skills/`;
5. copia `setup-godot-mcp.ps1` e `dump-godot-api.ps1` para `tools/` do projeto;
6. acrescenta o bloco de ferramentas ao `AGENTS.md` (se ainda não existir);
7. cria `opencode.json` se ainda não existir — se existir, ele **não** sobrescreve: compare com `opencode.example.jsonc` e ajuste à mão.

Nada disso toca em cenas, scripts ou configurações do seu jogo.

Depois:

1. Abra o projeto no Godot — o plugin sobe sozinho e a ponte escuta em `ws://127.0.0.1:6550`.
2. Abra o OpenCode na pasta do projeto.
3. Peça: **"conecte ao Godot"** (ou carregue a skill `godot-live`).

## Uso

Com a ponte ativa, o agente pode:

```text
"Mostre a árvore de cena atual"
"Rode res://scenes/main.tscn e me diga se há erros"
"Aperte jump, espere 30 frames e capture um screenshot"
"Adicione um OmniLight3D no topo do nó Actors e salve"
"Qual a assinatura de CharacterBody3D.move_and_slide?"
```

### Validação padrão que a skill ensina

```
godot_editor_run_scene  →  godot_runtime_status  →  godot_runtime_wait
                       →  godot_runtime_capture_screenshot
                       →  godot_editor_get_errors (count deve ser 0)
                       →  godot_editor_stop_scene
```

## Instalação manual

Se preferir não usar o script:

```powershell
git clone https://github.com/alexmeckes/godot-mcp "$HOME\Tools\godot-mcp"
cd "$HOME\Tools\godot-mcp"; npm install; npm run build

Copy-Item -Recurse addons\godot_ai_bridge "C:\seu-projeto\addons\"
Copy-Item -Recurse <kit>\.opencode "C:\seu-projeto\"
```

E adicione ao `project.godot`:

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/godot_ai_bridge/plugin.cfg")
```

E ao `opencode.json` (formato V2):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "godot": {
        "type": "local",
        "command": ["node", "C:/Users/voce/Tools/godot-mcp/dist/index.js"],
        "cwd": "."
      }
    }
  }
}
```

## Segurança

- A ponte dá **execução de GDScript arbitrário** no editor. É poder total sobre o projeto.
- O servidor e o addon escutam apenas em **loopback** (`127.0.0.1`).
- O pareamento usa token em `.godot/godot-ai-bridge.json`, gerado na primeira ativação.
  `.godot/` já é ignorado pelo Git do Godot — **nunca** versione esse arquivo.
- Não exponha a porta 6550 à rede.

## Solução de problemas

| Sintoma | Causa provável | Correção |
|---|---|---|
| `pairing credentials are unavailable` | plugin nunca rodou | confirme `[editor_plugins]` e reinicie o **editor** |
| `connected: false` com a porta fechada | editor fechado | reabra o editor; refaça `godot_connect` |
| `No active runtime debug session` | corrida de boot do harness | aguarde 1–2 s e repita |
| `Parse error` ao executar GDScript | o wrapper exige `return` | termine o código com `return <valor>` |
| Driver `opengl3` com `d3d12` configurado | renderer Compatibility | use `forward_plus` ou remova a chave D3D12 |
| Mudou `rendering_method` e nada mudou | renderer é lido no boot | reinicie o editor |

## Desinstalar

```powershell
Remove-Item -Recurse "C:\seu-projeto\addons\godot_ai_bridge"
Remove-Item -Recurse "C:\seu-projeto\.opencode\skills\godot-live"
# remova [editor_plugins] do project.godot e o bloco mcp.servers.godot do opencode.json
```

## Licença

MIT — veja [LICENSE](LICENSE). O addon e o servidor pertencem ao projeto
[alexmeckes/godot-mcp](https://github.com/alexmeckes/godot-mcp), também MIT.
Godot Engine é © seus contribuidores.
