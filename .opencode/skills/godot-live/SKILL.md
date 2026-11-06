---
name: Godot Live
description: Conectar e operar o editor Godot 4 via MCP (ferramentas godot_*), rodar cenas, inspecionar a árvore de nós, simular input e capturar screenshots para validar mudanças.
---

# Godot Live (MCP)

Integração ao vivo com o editor Godot. Use sempre que precisar **executar, inspecionar ou validar** o jogo, em vez de apenas editar arquivos.

## Pré-requisitos

| Peça | Onde fica |
|---|---|
| Servidor MCP | `~/Tools/godot-mcp/dist/index.js` (ou onde o instalador colocou) |
| Config de conexão | `opencode.json` → `mcp.servers.godot` |
| Addon no projeto | `res://addons/godot_ai_bridge/` |
| Plugin ativo | `project.godot` → `[editor_plugins]` |
| Token de pareamento | `.godot/godot-ai-bridge.json` (gerado ao ativar; **não versionar**) |

O servidor MCP sobe junto com o OpenCode. O que precisa existir é o **editor aberto** com o plugin ativo, ouvindo em `ws://127.0.0.1:6550`.

Se algo não bater, rode `tools/doctor.ps1` antes de qualquer tentativa e erro: ele confere Node, servidor,
dependências, addon, plugin, config, token, porta e versão da engine, e diz o que corrigir.

## Fluxo padrão

1. `godot_connection_status`
2. Se `connected: false`, diagnostique antes de qualquer coisa (seção "Recuperação").
3. `godot_connect` → deve retornar `success: true` e a versão da engine.
4. `godot_editor_get_project_info` para confirmar que é o projeto certo.
5. `godot_editor_get_scene_tree` para ver o estado real da cena aberta.

## Recuperação (editor fechado / ponte caída)

Primeiro tente o diagnóstico do kit — ele responde o que está faltando sem tentativa e erro:

```powershell
powershell -ExecutionPolicy Bypass -File tools/doctor.ps1
```

Se o problema for o editor fechado:

```powershell
# 1. Verificar se a porta esta ouvindo
Get-NetTCPConnection -LocalPort 6550 -State Listen

# 2. Verificar se o editor esta rodando
Get-Process -Name "Godot*"

# 3. Reabrir o editor (ajuste o caminho do binario)
& "C:\Godot\Godot_v4.7.2-stable_win64.exe" --path "C:\caminho\do\projeto" --editor
```

Depois de reabrir o editor, a sessão WebSocket anterior morre: chame `godot_disconnect` e `godot_connect` de novo.

Se `godot_connect` disser *"pairing credentials are unavailable"*, o plugin nunca rodou: confirme `[editor_plugins]` no `project.godot` e reinicie o **editor** (não basta rodar o jogo).

## Validação obrigatória após mudanças

```
godot_editor_run_scene({ scenePath: "res://scenes/main.tscn" })
godot_runtime_status()          # repetir ate available: true (o harness sobe 1-2 s depois)
godot_runtime_wait({ frames: 60 })
godot_runtime_capture_screenshot({ path: "C:/Users/<voce>/AppData/Local/Temp/check.png" })
godot_editor_get_errors()       # deve retornar count: 0
godot_editor_stop_scene()
```

`godot_runtime_status` logo após `run_scene` pode falhar com *"No active runtime debug session"* — é corrida de inicialização, não erro do jogo. Aguarde e repita.

## Peculiaridades conhecidas

- **`godot_editor_execute_gdscript` exige `return` explícito.** O bridge envolve o código em `func __mcp_exec(...) -> Variant`; `pass` ou `print("x")` sozinhos dão "Parse error". Sempre termine com `return <valor>`.
- **Trocar renderer exige reiniciar o editor.** `rendering_method` é lido na inicialização; o driver efetivo só muda após reabrir.
- **`rendering_device/driver.windows` não tem efeito sob `gl_compatibility`.** Se o driver reportado for `opengl3`, o D3D12 está inerte.
- **Screenshot do runtime** usa o viewport do jogo, não o editor.
- **`GodotAIBridgeRuntime` é autoload de desenvolvimento** — nunca referencie em código de jogo.
- Alterações de arquivo feitas por fora do editor podem exigir `godot_editor_refresh_filesystem`.
- O `opencode.json` recarrega sozinho; **fechar o editor** é o que derruba a ponte.

## Ferramentas por categoria

| Preciso de | Ferramentas |
|---|---|
| Inspecionar cena | `godot_editor_get_scene_tree`, `godot_editor_select_node` |
| Editar cena ao vivo | `godot_editor_add_node`, `godot_editor_modify_node`, `godot_editor_remove_node`, `godot_editor_save_scene` |
| Editar arquivos | `godot_read_scene`, `godot_write_scene`, `godot_read_script`, `godot_write_script`, `godot_validate_scene` |
| Rodar/depurar | `godot_editor_run_scene`, `godot_editor_stop_scene`, `godot_editor_get_output`, `godot_editor_get_errors` |
| Testar gameplay | `godot_runtime_tap_action`, `godot_runtime_click`, `godot_runtime_type_text`, `godot_runtime_capture_screenshot` |
| InputMap | `godot_input_list_actions`, `godot_input_set_action`, `godot_input_apply_preset` |
| UI / tema | `godot_ui_create_theme`, `godot_ui_create_menu`, `godot_ui_create_hud` |
| Áudio | `godot_audio_create_bus_layout`, `godot_audio_configure_player` |
| Dúvida de API | `godot_get_class_docs`, `godot_search_docs`, `godot_help` |

## Regras de ouro

- Não renomear nós existentes sem autorização.
- Toda mudança estrutural termina com execução + screenshot + `get_errors` limpo.
- Prefira nós nativos e recursos (`Resource`) a código imperativo repetido.
