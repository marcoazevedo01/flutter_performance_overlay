# Registro de Alterações (Changelog)

Todas as alterações notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado no [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

---

## [0.2.0] - 2026-11-18

### Segurança e Alterações
- **Autenticação Segura no `PerformanceRemoteRelay` (`remote_relay_io`, `remote_relay_web`, `remote_relay_protocol`)**:
  - Removida a anexação de `?key=` na query string da URL WebSocket em `RemoteRelayProtocol.buildUri`.
  - Autenticação via header HTTP `x-perf-key` (IO) ou frame inicial `{"type": "auth", ...}` via `RemoteRelayProtocol.buildAuthPayload` (suporte a `relayKey` e `authToken`).
- **Sanitização Automática de Logs e Erros (`sanitizeLogs = true`)**:
  - Novo parâmetro `sanitizeLogs` em `PerformanceOverlayConfig` e `PerformanceMonitorService` (ativo por padrão) que redige automaticamente `Bearer` tokens, headers `Authorization`, campos sensíveis (`token`, `access_token`, `refresh_token`, `authToken`, `senha`, `password`, `secret`, `apiKey`, `x-perf-key`, `cpf`, `cnpj`) e CPF/CNPJ formatados antes de incluir nos chunks, truncando mensagens acima de `8192` caracteres.
- **Hardening do `PerformanceDevBridge`**:
  - Padrão de `enableDevBridge` alterado para `kDebugMode` em `PerformanceOverlayConfig` e `PerformanceMonitorService`.
  - CORS restrito a origens locais (`http`/`https` em `localhost`, `127.0.0.1` e `::1`), respondendo `403` para origens externas.

---

## [0.1.9] - 2026-11-18

### Adicionado
- **Resiliência para Redes Móveis (3G/4G Android) no `PerformanceRemoteRelay`**:
  - `pingInterval` de 15s no WebSocket `dart:io` para detecção rápida de quedas silenciosas em operadoras móveis.
  - Buffer circular em memória (até 10 chunks pendentes) que retém lotes gerados durante janelas de desconexão e os descarrega automaticamente ao reconectar.
  - Reconexão imediata ao retornar do background (`AppLifecycleState.resumed`) via `WidgetsBindingObserver`.

---

## [0.1.8] - 2026-11-18

### Adicionado
- **Auto-detecção Automática de Versão, App e Usuário na Lib**:
  - Leitura automática de `version.json`, `MethodChannel` (`package_info_plus` quando presente), `pubspec.yaml` em dev e usuário do SO (`USERNAME`/`USER`), com método `updateMetadata()` e sincronização no `PerformanceOverlayWidget.didUpdateWidget`.
- **Detecção de Quedas e Status de Reconexão (`RelayConnectionStatus`)**:
  - Callback `onStatusChanged` no `PerformanceRemoteRelay` (`disconnected`, `connecting`, `connected`, `reconnecting`) e método `refreshRegistration()` para atualizar metadados em tempo real.

---

## [0.1.7] - 2026-11-18

### Adicionado
- **Relay WebSocket Remoto Multiplataforma (`PerformanceRemoteRelay`)**:
  - Cliente WebSocket nativo (`dart:io` e `dart:js_interop` na Web) sem dependências externas, com modo passivo para apps (`register`, `start`, `stop`, `chunk`) e modo `isInspector: true` para painéis de suporte (`list`, `start_target`, `stop_target`).
  - Configuração opcional em `PerformanceOverlayConfig` e `PerformanceMonitorService` (`remoteRelayUrl`, `remoteRelayKey`, `appName`, `userName`, `deviceName`, `appVersion`) sem URLs ou chaves hardcoded.
- **Auto-detecção de `appName` e `deviceName`**:
  - Inferência automática por plataforma (executável/SO/hostname no IO e `document.title` na Web) e inclusão de `appName` e `instanceId` nos chunks de streaming.
- **DevBridge Multi-Porta e Rotas de Streaming Local**:
  - Bind automático na primeira porta livre de `127.0.0.1:8765..8774` (`shared: false`) para coexistência de múltiplos apps na mesma máquina.
  - Novos endpoints `/stream/start`, `/stream/stop`, `/stream/chunk` e metadados expandidos no `/health`.

---

## [0.1.6] - 2026-11-18

### Adicionado
- **Streaming Remoto Contínuo em Modo Headless (`startStreaming` / `stopStreaming`)**:
  - Controle sob demanda no `PerformanceMonitorService` para iniciar e encerrar coleta de telemetria em background sem exibir o overlay visual na tela do usuário.
  - Emissão periódica de lotes JSON (`onChunk`) contendo `currentMetrics`, `samples` acumuladas no intervalo, `diagnostics`, `rebuilds`, `logs` e `errors`, com drenagem automática de buffers entre lotes e limites de segurança em memória.
  - Interceptação encadeada e reversível de `debugPrint`, `FlutterError.onError` e `PlatformDispatcher.instance.onError`, mantendo os handlers originais do app intactos após o encerramento.
- **Proteção de Sessão Headless no `PerformanceOverlayWidget`**:
  - Ocultar o overlay (`enabled: false`) não interrompe mais uma sessão de streaming remoto em andamento (`isStreaming`).
- **Delta de Memória da Sessão (`sessionDeltaMemoryMb` / `ΔSessão`)**:
  - Persistência do baseline inicial de memória por processo (`pid` em arquivo temporário com cache em RAM no IO e `window.__fpoBaselineMemoryMb` na Web), sobrevivendo a ciclos de *Hot Reload* e *Hot Restart*.
  - Novo badge `ΔSessão` no painel expandido do `PerformanceOverlayWidget` e serialização de `sessionDeltaMemoryMb` em `PerformanceData.toJson()`.
  - Nova regra em `PerformanceDiagnostics` para alertar sobre acúmulo contínuo de memória na sessão (`> 30MB` aviso, `> 100MB` crítico), com redefinição do baseline integrada ao `clearHistory()`.

### Corrigido
- **Fechamento de Socket Órfão no `PerformanceDevBridge`**:
  - Rastreamento ativo de servidores por porta para encerrar instâncias HTTP anteriores antes de um novo `HttpServer.bind`, evitando retenção de objetos após *Hot Restart*.

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
