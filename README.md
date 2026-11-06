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
| `tools/setup-godot-mcp.ps1` | Só a parte servidor (clone/atualização + `npm ci` + build) + addon + `[editor_plugins]` |
| `tools/doctor.ps1` | Diagnóstico: ambiente, servidor, dependências, addon, plugin, config, token, ponte e versões |
| `tools/dump-godot-api.ps1` | Extrai a referência da API do **seu** binário Godot (XML + JSON) |
| `.opencode/skills/godot-live/` | Skill com o procedimento: conectar, diagnosticar, validar, peculiaridades |
| `opencode.example.jsonc` | Configuração MCP no formato **V2** (`mcp.servers`) |
| `AGENTS-snippet.md` | Bloco para colar no `AGENTS.md` do projeto |

O servidor usado é o [alexmeckes/godot-mcp](https://github.com/alexmeckes/godot-mcp) (MIT).
O kit **não redistribui** o addon: ele baixa e compila na sua máquina.

## Requisitos

- **Godot 4.x** — testado em `4.7.2-stable`
- **Node.js 20 ou superior** — o instalador verifica e aborta com mensagem clara se não atender
- **Git** — necessário apenas para baixar/atualizar o servidor
- **OpenCode V2** (funciona com qualquer cliente MCP que suporte servidores `stdio`)
- Windows + PowerShell (testado no Windows PowerShell 5.1 e no PowerShell 7; os scripts são
  deliberadamente ASCII puro para não depender da detecção de codificação do PS 5.1)

## Instalação

```powershell
git clone https://github.com/wagnecorreia/godot-live-mcp-kit.git
cd godot-live-mcp-kit
powershell -ExecutionPolicy Bypass -File tools/install.ps1 -ProjectPath "C:\caminho\do\seu-projeto-godot"
```

O instalador é idempotente (pode rodar de novo sem duplicar nada) e termina com o diagnóstico.
Ele:

1. confere **Node.js ≥ 20** e npm (aborta explicando como corrigir);
2. clona o `godot-mcp` em `~/Tools/godot-mcp` (ou em `-InstallDir`) ou **atualiza por fast-forward**
   se já existir e estiver limpo — nunca descarta alterações locais;
3. instala dependências de forma reproduzível (`npm ci` quando o `package-lock.json` mudou) e compila;
4. copia `addons/godot_ai_bridge` (só quando difere do upstream);
5. registra o plugin em `[editor_plugins]` do `project.godot`, preservando plugins que já estejam lá;
6. copia a skill `godot-live` para `.opencode/skills/` (atualiza só se mudou);
7. copia `setup-godot-mcp.ps1`, `dump-godot-api.ps1` e `doctor.ps1` para `tools/` do projeto;
8. acrescenta o bloco de ferramentas ao `AGENTS.md` (se ainda não existir);
9. cria `opencode.json` se faltar ou **mescla** `mcp.servers.godot` se já existir, preservando os
   demais servidores, `instructions`, `permissions` e qualquer outra chave;
10. roda `tools/doctor.ps1` e retorna código de saída diferente de zero em caso de falha.

Tudo que é alterado passa antes por backup em `.kit-backup/` na raiz do projeto
(`project.godot`, `AGENTS.md`, `opencode.json`, addon e skill). Nada disso toca em cenas,
scripts ou configurações do seu jogo.

Depois:

1. Abra o projeto no Godot — o plugin sobe sozinho e a ponte escuta em `ws://127.0.0.1:6550`.
2. Abra o OpenCode na pasta do projeto.
3. Peça: **"conecte ao Godot"** (ou carregue a skill `godot-live`).

## Atualizar

Rode o mesmo comando de instalação. O servidor é atualizado por `git pull --ff-only` quando o
clone está limpo. Se você mexeu em arquivos do servidor, ele **não** atualiza e mostra exatamente
quais arquivos estão alterados — resolva ou remova a pasta para reinstalar limpo.

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1   # só o servidor/addon
powershell -ExecutionPolicy Bypass -File tools/setup-godot-mcp.ps1 -SkipUpdate
```

## Diagnóstico

```powershell
powershell -ExecutionPolicy Bypass -File tools/doctor.ps1
```

Verifica Node/npm/git, `dist/`, `node_modules` vs `package-lock.json`, commit do clone, addon
completo, plugin ativo, `opencode.json`, token de pareamento, porta 6550 e compatibilidade de
versão entre engine e projeto. Pode rodar com o editor fechado: o que depende do editor aparece
como **AVISO**, não como falha. Sai com código 1 só quando há **FALHA**.

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
| `Node.js nao encontrado` / `exige 20 ou superior` | Node ausente ou antigo | instale Node 20+ e abra um terminal novo |
| `npm ci falhou` | `package-lock.json` fora de sincronia com o upstream | apague `node_modules` e rode de novo; se persistir, remova `~/Tools/godot-mcp` |
| `Ha alteracoes locais ... atualizacao ignorada` | você editou o clone do servidor | veja os arquivos listados; `git checkout -- .` no clone ou remova a pasta |
| `opencode.json nao e JSON puro` | comentários em `.json` | renomeie para `opencode.jsonc` ou remova os comentários; o instalador mostra o bloco pronto |
| `opencode.json aponta para caminho inexistente` | servidor mudou de lugar | rode o instalador com `-InstallDir` do novo caminho e ajuste o `command` |
| `pairing credentials are unavailable` | plugin nunca rodou | confirme `[editor_plugins]` e reinicie o **editor** |
| `connected: false` com a porta fechada | editor fechado | reabra o editor; refaça `godot_connect` |
| `No active runtime debug session` | corrida de boot do harness | aguarde 1–2 s e repita |
| `Parse error` ao executar GDScript | o wrapper exige `return` | termine o código com `return <valor>` |
| Driver `opengl3` com `d3d12` configurado | renderer Compatibility | use `forward_plus` ou remova a chave D3D12 |
| Mudou `rendering_method` e nada mudou | renderer é lido no boot | reinicie o editor |

Em qualquer um desses casos, `tools/doctor.ps1` diz qual peça está faltando ou desalinhada.

## Desinstalar

```powershell
Remove-Item -Recurse "C:\seu-projeto\addons\godot_ai_bridge"
Remove-Item -Recurse "C:\seu-projeto\.opencode\skills\godot-live"
Remove-Item -Recurse "C:\seu-projeto\.kit-backup"
# remova [editor_plugins] do project.godot e o bloco mcp.servers.godot do opencode.json
```

## Licença

MIT — veja [LICENSE](LICENSE). O addon e o servidor pertencem ao projeto
[alexmeckes/godot-mcp](https://github.com/alexmeckes/godot-mcp), também MIT.
Godot Engine é © seus contribuidores.
