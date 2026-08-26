## 0.1.0

* Lançamento inicial do `flutter_performance_overlay`.
* Monitoramento de FPS instantâneo e médio com coloração reativa.
* Métricas de UI Build Time (Dart thread) e Raster/GPU Duration.
* Cálculo de taxa de quadros perdidos (Jank %) e duração do pior frame (Worst Frame).
* Monitoramento de consumo de memória RAM RSS, Delta RAM e Pico da sessão.
* Detector de congelamento de Event Loop / UI Freeze na thread principal do Dart.
* Rastreamento de rotas ativas com `PerformanceRouteObserver`.
* Contador e auditoria de reconstruções com `PerformanceRebuildTracker` e widget `TrackRebuild`.
* Overlay arrastável e interativo com clamping inteligente aos limites da tela (`SafeArea`).
* Mini-servidor local `PerformanceDevBridge` (HTTP) e Servidor MCP (`perf_mcp_server`) para integração com agentes de IA (Antigravity, Cursor, Claude).
