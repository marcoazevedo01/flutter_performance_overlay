class PerformanceData {
  /// Taxa de quadros por segundo instantânea calculada a partir do último frame.
  final double currentFps;

  /// Média móvel de FPS na janela configurada.
  final double averageFps;

  /// Duração média da UI thread (build e layout) na janela recente em milissegundos.
  final double uiDurationMs;

  /// Duração média da Raster/GPU thread na janela recente em milissegundos.
  final double rasterDurationMs;

  /// Percentual de frames que excederam o orçamento da taxa de atualização (Jank).
  final double jankPercentage;

  /// Duração do frame mais lento registrado na janela recente em milissegundos.
  final double worstFrameMs;

  /// Memória RSS atual do processo em Megabytes.
  final double memoryRssMb;

  /// Variação de memória RAM RSS em relação à última leitura (Delta RAM) em Megabytes.
  final double deltaMemoryRssMb;

  /// Variação de memória RAM acumulada desde a entrada na rota ativa em Megabytes.
  final double routeDeltaMemoryMb;

  /// Pico máximo de memória RSS registrado durante a execução da sessão.
  final double peakMemoryRssMb;

  /// Atraso detectado na fila de eventos (Event Loop) do Dart em milissegundos.
  final double eventLoopLagMs;

  /// Nome da rota ou tela ativa no momento.
  final String currentRoute;

  /// Total acumulado de rebuilds rastreados em widgets instrumentados.
  final int rebuildCount;

  /// Latência média recente de chamadas de rede/HTTP em milissegundos.
  final double httpLatencyMs;

  /// Tempo de montagem e estabilização do frame de carga da rota em milissegundos.
  final double routeMountDurationMs;

  /// Carimbo de data/hora do registro da métrica.
  final DateTime timestamp;

  const PerformanceData({
    required this.currentFps,
    required this.averageFps,
    required this.uiDurationMs,
    required this.rasterDurationMs,
    required this.jankPercentage,
    required this.worstFrameMs,
    required this.memoryRssMb,
    required this.deltaMemoryRssMb,
    this.routeDeltaMemoryMb = 0.0,
    required this.peakMemoryRssMb,
    required this.eventLoopLagMs,
    required this.currentRoute,
    required this.rebuildCount,
    this.httpLatencyMs = 0.0,
    this.routeMountDurationMs = 0.0,
    required this.timestamp,
  });

  factory PerformanceData.initial() => PerformanceData(
        currentFps: 60.0,
        averageFps: 60.0,
        uiDurationMs: 0.0,
        rasterDurationMs: 0.0,
        jankPercentage: 0.0,
        worstFrameMs: 16.6,
        memoryRssMb: 0.0,
        deltaMemoryRssMb: 0.0,
        routeDeltaMemoryMb: 0.0,
        peakMemoryRssMb: 0.0,
        eventLoopLagMs: 0.0,
        currentRoute: '/',
        rebuildCount: 0,
        httpLatencyMs: 0.0,
        routeMountDurationMs: 0.0,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'currentFps': double.parse(currentFps.toStringAsFixed(1)),
        'averageFps': double.parse(averageFps.toStringAsFixed(1)),
        'uiDurationMs': double.parse(uiDurationMs.toStringAsFixed(2)),
        'rasterDurationMs': double.parse(rasterDurationMs.toStringAsFixed(2)),
        'jankPercentage': double.parse(jankPercentage.toStringAsFixed(1)),
        'worstFrameMs': double.parse(worstFrameMs.toStringAsFixed(1)),
        'memoryRssMb': double.parse(memoryRssMb.toStringAsFixed(2)),
        'deltaMemoryRssMb': double.parse(deltaMemoryRssMb.toStringAsFixed(2)),
        'routeDeltaMemoryMb': double.parse(routeDeltaMemoryMb.toStringAsFixed(2)),
        'peakMemoryRssMb': double.parse(peakMemoryRssMb.toStringAsFixed(2)),
        'eventLoopLagMs': double.parse(eventLoopLagMs.toStringAsFixed(1)),
        'currentRoute': currentRoute,
        'rebuildCount': rebuildCount,
        'httpLatencyMs': double.parse(httpLatencyMs.toStringAsFixed(1)),
        'routeMountDurationMs': double.parse(routeMountDurationMs.toStringAsFixed(1)),
      };

  PerformanceData copyWith({
    double? currentFps,
    double? averageFps,
    double? uiDurationMs,
    double? rasterDurationMs,
    double? jankPercentage,
    double? worstFrameMs,
    double? memoryRssMb,
    double? deltaMemoryRssMb,
    double? routeDeltaMemoryMb,
    double? peakMemoryRssMb,
    double? eventLoopLagMs,
    String? currentRoute,
    int? rebuildCount,
    double? httpLatencyMs,
    double? routeMountDurationMs,
    DateTime? timestamp,
  }) {
    return PerformanceData(
      currentFps: currentFps ?? this.currentFps,
      averageFps: averageFps ?? this.averageFps,
      uiDurationMs: uiDurationMs ?? this.uiDurationMs,
      rasterDurationMs: rasterDurationMs ?? this.rasterDurationMs,
      jankPercentage: jankPercentage ?? this.jankPercentage,
      worstFrameMs: worstFrameMs ?? this.worstFrameMs,
      memoryRssMb: memoryRssMb ?? this.memoryRssMb,
      deltaMemoryRssMb: deltaMemoryRssMb ?? this.deltaMemoryRssMb,
      routeDeltaMemoryMb: routeDeltaMemoryMb ?? this.routeDeltaMemoryMb,
      peakMemoryRssMb: peakMemoryRssMb ?? this.peakMemoryRssMb,
      eventLoopLagMs: eventLoopLagMs ?? this.eventLoopLagMs,
      currentRoute: currentRoute ?? this.currentRoute,
      rebuildCount: rebuildCount ?? this.rebuildCount,
      httpLatencyMs: httpLatencyMs ?? this.httpLatencyMs,
      routeMountDurationMs: routeMountDurationMs ?? this.routeMountDurationMs,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
