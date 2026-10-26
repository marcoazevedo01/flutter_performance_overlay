# Registro de Alterações (Changelog)

Todas as alterações notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado no [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

---

## [0.1.5] - 2026-10-24

### Adicionado
- **Dart VM Service Extensions (`PerformanceServiceExtensions`)**:
  - Registro de extensões RPC nativas na VM Dart (`ext.flutter_performance.getMetrics`, `ext.flutter_performance.getHistory`, `ext.flutter_performance.getRebuilds`, `ext.flutter_performance.diagnose`, `ext.flutter_performance.reset`).
  - Habilita integração direta com o ecossistema Dart/Flutter MCP (`dart mcp-server`), Dart Tooling Daemon (DTD) e Flutter DevTools sem dependência obrigatória de portas de rede TCP locais ou redirecionamentos `adb forward`.
  - Despachante estático centralizado com proteção contra registros duplicados no Isolate e ciclo de vida atrelado a `PerformanceMonitorService`.
- **Parâmetro `enableServiceExtensions` em `PerformanceMonitorService`**:
  - Flag para habilitar ou desabilitar o registro das rotas na Dart VM Service (padrão: `true`).

---

## [0.1.4] - 2026-10-24

### Adicionado
- **Histórico Circular de Rotas (`routeHistory` / `RouteHistoryEntry`)**:
  - Buffer circular em memória com as últimas 10 rotas navegadas, retendo para cada tela: `mountDurationMs` (*Time-to-Mount*), `deltaMemoryMb` (variação líquida de RAM), `worstFrameMs` (pior frame de jank registrado durante a permanência) e timestamp.
  - Exportação serializada em `PerformanceData.toJson()` e no payload global `window.__flutterPerformanceMetrics`.
- **Cliente HTTP Transparente (`PerformanceHttpClient`)**:
  - Implementação de `http.BaseClient` que intercepta requisições automaticamente e alimenta o `PerformanceNetworkTracker`.
  - Método helper estático `PerformanceNetworkTracker.track<T>()` para medição imediata de blocos assíncronos.
- **Diagnóstico de Risco Crítico de Memória / OOM**:
  - Nova regra em `PerformanceDiagnostics` que emite alerta de severidade quando o consumo de memória ultrapassa 1.0 GB (ou pico crítico), prevenindo travamentos de abas no navegador.

---

## [0.1.3] - 2026-10-24

### Adicionado
- **Ponte de Telemetria Web via JS Interop (`window.__flutterPerformanceMetrics`)**:
  - Exportação contínua de métricas estruturadas e array de problemas (`issues`) no objeto `window` no Flutter Web.
  - Permite auditoria direta por Puppeteer, Chrome DevTools Protocol e agentes MCP mesmo sob o sandbox do navegador (onde servidores de socket TCP são bloqueados).
- **Tempo de Montagem de Rotas (`routeMountDurationMs`)**:
  - Medição do tempo decorrido desde o disparo da navegação até a conclusão da transição e montagem da nova tela.
  - Integrado em `PerformanceData` e visualizado em relatórios e telemetria.
- **Helper Global de Acessibilidade Web (`window.__enableFlutterSemantics()`)**:
  - Função exposta no Chromium para acionar programaticamente a árvore de semântica do Flutter Web (CanvasKit/Skwasm), viabilizando cliques e preenchimentos automatizados de inputs por agentes de IA e testes e2e.
- **Rastreador de Latência HTTP (`PerformanceNetworkTracker`)**:
  - Utilitário desacoplado para registrar durações de requisições HTTP e computar latência média com decaimento exponencial (`httpLatencyMs`).
- **Suavização EMA (Exponential Moving Average) no Heap Web**:
  - Aplicação de filtro com $\alpha = 0.2$ na leitura de `usedJSHeapSize` para eliminar oscilações abruptas causadas pelos ciclos frequentes de Garbage Collection do navegador.

---

## [0.1.2] - 2026-10-23

### Adicionado
- **Suporte a Memória RAM no Flutter Web**:
  - Extração nativa de `usedJSHeapSize` via JS Interop (`dart:js_interop`) para navegadores Chromium (Chrome, Edge, Brave).
  - Tratamento elegante com fallback `RAM: N/A` para plataformas ou navegadores que restringem telemetria de heap (Firefox, Safari).
- **Rastreamento de Memória por Rota Ativa ($\Delta\text{Rota}$)**:
  - Adicionado o campo `routeDeltaMemoryMb` em `PerformanceData` e flag `showRouteDeltaMemory` em `PerformanceOverlayConfig`.
  - Badge visual `ΔRota: +X.XMB` no modo expandido do overlay, medindo o acúmulo contínuo de memória desde a navegação na tela.
  - Alerta de auditoria automática em `PerformanceDiagnostics` para telas que acumulam $> 15.0\text{MB}$ de RAM.

### Modificado
- **Aprimoramento do $\Delta\text{RAM}$**:
  - Taxa normalizada em `MB/s` baseada no tempo real decorrido entre leituras.
  - *Deadband* (zona morta) de $\pm 0.1\text{MB/s}$ para ignorar ruído transitório do Garbage Collector.
  - Decaimento visual suave que mantém picos transitórios de alocação visíveis por $\sim 1.5\text{s}$ antes de zerar.

---

## [0.1.1] - 2026-08-25

### Adicionado
- **Auto-Atualização Transparente no Servidor MCP**:
  - O `perf_mcp_server.dart` agora verifica novidades no GitHub em segundo plano (`background`) de forma assíncrona, sem bloquear o handshake do agente.
  - Sobrescrita automática do script local quando novas ferramentas ou melhorias forem publicadas.
- **Documentação e Guias**:
  - Instruções de setup em comando único para Windows (PowerShell) e Linux/macOS.
  - Atualização do README com documentação completa em português.

---

## [0.1.0] - 2026-08-25

### Adicionado
- **Widget de Overlay de Desempenho (`PerformanceOverlayWidget`)**:
  - Overlay interativo, arrastável e expansível com alternância por toque (modo compacto $\leftrightarrow$ expandido).
  - Contenção inteligente nos limites da tela (`SafeArea`), impedindo que o card saia do campo de visão.
  - Monitoramento de FPS em tempo real (instantâneo e média móvel) com alertas por cores.
  - Métricas de tempo de build na UI Thread (Dart) e tempo de rasterização na GPU Thread.
  - Cálculo de taxa de quadros perdidos (Jank %) e medição do pior frame recente.
  - Monitoramento de memória RAM RSS, taxa de variação ($\Delta\text{RAM}$) e pico da sessão.
  - Detector de congelamento de Event Loop / UI Freeze na thread principal do Dart.

- **Diagnósticos e Instrumentação**:
  - `PerformanceRouteObserver`: Rastreamento automático da tela/rota ativa no `Navigator` e `Flutter Modular`.
  - `PerformanceRebuildTracker`: Contador e rastreador de rebuilds com widget utilitário `<TrackRebuild id="..." />`.
  - `PerformanceDiagnostics`: Motor de auditoria automática que classifica gargalos por severidade.

- **DevBridge e Servidor MCP (Model Context Protocol)**:
  - Servidor HTTP local embutido (`PerformanceDevBridge`) na porta `8765` para telemetria ao vivo.
  - Servidor MCP autônomo (`perf_mcp_server.dart`) para que agentes de IA (Antigravity, Cursor, Claude) realizem auditorias autônomas de performance.

- **Qualidade e Testes**:
  - Bateria completa de testes anti-regressão (18 testes automatizados).
  - Conformidade total com o linter do Flutter.
