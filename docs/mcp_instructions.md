# Como Conectar o Agente de IA ao `flutter_performance_overlay` via MCP

O **Flutter Performance Overlay** inclui um servidor **MCP (Model Context Protocol)** e uma ponte HTTP local (**DevBridge**) que permite que assistentes e agentes autônomos (Antigravity, Claude Desktop, Cursor, etc.) inspecionem e diagnostiquem problemas de performance do seu app em tempo real.

---

## 🛠️ 1. Como Funciona

1. **No App Flutter**: Quando o app roda com o `PerformanceOverlayWidget` (em modo debug ou profile), o `PerformanceDevBridge` sobe automaticamente um servidor HTTP local leve em `http://127.0.0.1:8765`.
2. **No Agente**: O script `perf_mcp_server.dart` se conecta via JSON-RPC stdio e expõe ferramentas de telemetria para o agente.

---

## ⚙️ 2. Configurando o Servidor MCP no Antigravity / Cursor / Claude Desktop

Adicione a seguinte configuração no seu arquivo de configuração MCP (ex: `antigravity_mcp.json`, `claude_desktop_config.json` ou nas configurações do seu cliente MCP):

```json
{
  "mcpServers": {
    "flutter-performance": {
      "args": [
        "c:/Users/marco/Documents/git/coletor-mobile/packages/flutter_performance_overlay/bin/perf_mcp_server.dart"
      ],
      "command": "C:/tools/dart-sdk/bin/dart.exe"
    }
  }
}
```

> **Dica**: Se estiver em monorepo ou outra máquina, aponte para o caminho absoluto do arquivo `perf_mcp_server.dart`.

---

## 🧰 3. Ferramentas Disponíveis para o Agente

| Ferramenta MCP | O que ela faz |
| :--- | :--- |
| `get_live_metrics` | Retorna o snapshot ao vivo com FPS, UI Duration, GPU Duration, RAM, Delta RAM, Rota Atual e Rebuilds. |
| `audit_performance_issues` | Executa uma auditoria automática recente e lista problemas (Jank, UI/GPU bottleneck, Event Loop Lag, Memory leak suspect) com sugestões de correção de código. |
| `get_rebuild_hotspots` | Retorna o ranking dos widgets que mais sofreram rebuilds no app para otimização com `const` ou `RepaintBoundary`. |
| `analyze_performance_log_file` | Lê e processa qualquer arquivo JSON de log exportado em disco pelo app. |
| `reset_performance_metrics` | Zera os contadores para iniciar uma sessão de medição limpa. |

---

## 🔍 4. Exemplo de Prompt para o Agente

Você pode pedir diretamente ao agente:
- *"Audite a performance do app no estado atual e me diga se há algum gargalo de UI ou vazamento de memória."*
- *"Quais widgets estão tendo mais rebuilds nesta tela?"*
- *"Analise o arquivo de log de performance exportado em `.../perf_logs_12345.json` e me dê um resumo."*
