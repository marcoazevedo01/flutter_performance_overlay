import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show File, FileMode;
import 'memory_reader/memory_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/performance_data.dart';
import 'event_loop_lag_detector.dart';
import 'network_tracker.dart';
import 'performance_dev_bridge.dart';
import 'performance_diagnostics.dart';
import 'performance_service_extensions.dart';
import 'rebuild_tracker.dart';
import 'route_observer.dart';
import 'telemetry_bridge/telemetry_bridge.dart';

/// Serviço desacoplado para coleta contínua e análise de métricas de desempenho.
class PerformanceMonitorService {
  /// Quantidade de frames mantidos na janela deslizante para cálculo de médias.
  final int windowFrameSize;

  /// Intervalo de atualização do ValueNotifier / callback na UI.
  final Duration refreshInterval;

  /// Intervalo para salvar métricas em arquivo (se [exportFilePath] for informado).
  final Duration exportInterval;

  /// Caminho do arquivo JSON de exportação de métricas.
  final String? exportFilePath;

  /// Limite em milissegundos para considerar que um frame teve Jank (padrão: 16.6ms para 60Hz).
  final double jankThresholdMs;

  /// Se deve habilitar o servidor HTTP local (DevBridge) para integração com agentes de IA (MCP).
  final bool enableDevBridge;

  /// Se deve registrar extensões nativas no Dart VM Service (MCP, DTD e DevTools).
  final bool enableServiceExtensions;

  /// Porta para o servidor local DevBridge.
  final int devBridgePort;

  final Queue<FrameTiming> _frameTimings = Queue<FrameTiming>();
  final List<PerformanceData> _history = [];

  Timer? _exportTimer;
  Timer? _uiRefreshTimer;
  late final EventLoopLagDetector _lagDetector;
  PerformanceDevBridge? _devBridge;
  PerformanceServiceExtensions? _serviceExtensions;

  double _previousMemoryRssMb = 0.0;
  double _peakMemoryRssMb = 0.0;
  DateTime? _lastMemorySampleTime;
  double _decayingDeltaRate = 0.0;
  String _lastObservedRoute = '';
  double _memoryOnRouteEntryMb = -1.0;
  double _routeDeltaMemoryMb = 0.0;
  DateTime? _routeEnteredAt;
  double _routeMountDurationMs = 0.0;
  double _worstFrameInCurrentRoute = 0.0;
  final List<RouteHistoryEntry> _routeHistory = [];
  bool _isRunning = false;

  void Function(PerformanceData data)? onMetricsUpdated;

  PerformanceData _lastData = PerformanceData.initial();
  PerformanceData get lastData => _lastData;

  /// Histórico imutável de leituras de performance coletadas.
  List<PerformanceData> get history => List.unmodifiable(_history);

  /// Histórico circular das últimas rotas navegadas e suas métricas consolidadas.
  List<RouteHistoryEntry> get routeHistory => List.unmodifiable(_routeHistory);

  /// Extensões nativas registradas na Dart VM Service (se habilitado).
  PerformanceServiceExtensions? get serviceExtensions => _serviceExtensions;

  PerformanceMonitorService({
    this.windowFrameSize = 60,
    this.refreshInterval = const Duration(milliseconds: 500),
    this.exportInterval = const Duration(seconds: 10),
    this.exportFilePath,
    this.jankThresholdMs = 16.6,
    this.enableDevBridge = true,
    this.enableServiceExtensions = true,
    this.devBridgePort = 8765,
  }) {
    _lagDetector = EventLoopLagDetector(
      interval: const Duration(milliseconds: 200),
    );

    if (enableDevBridge && !kIsWeb) {
      _devBridge = PerformanceDevBridge(
        port: devBridgePort,
        monitorService: this,
      );
    }

    if (enableServiceExtensions && !kIsWeb) {
      _serviceExtensions = PerformanceServiceExtensions(
        monitorService: this,
      );
    }
  }

  /// Inicia a coleta de métricas, o DevBridge, extensões de serviço e os timers periódicos.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    SchedulerBinding.instance.addTimingsCallback(_onReportTimings);
    _lagDetector.start();
    _devBridge?.start();
    _serviceExtensions?.register();

    _uiRefreshTimer = Timer.periodic(refreshInterval, (_) {
      _computeMetrics();
      final issues = PerformanceDiagnostics.analyze(
        currentData: _lastData,
        history: _history,
        rebuildsByWidget: PerformanceRebuildTracker().rebuildsByWidget,
      );
      final exportMap = {
        ..._lastData.toJson(),
        'issuesCount': issues.length,
        'issues': issues.map((e) => e.toJson()).toList(),
      };
      WebTelemetryBridge.export(exportMap);
      if (onMetricsUpdated != null) {
        onMetricsUpdated!(_lastData);
      }
    });

    if (exportFilePath != null && !kIsWeb) {
      _exportTimer = Timer.periodic(exportInterval, (_) {
        _exportMetricsToFile();
      });
    }
  }

  /// Para temporariamente a coleta de métricas e o DevBridge.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;

    SchedulerBinding.instance.removeTimingsCallback(_onReportTimings);
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
    _exportTimer?.cancel();
    _exportTimer = null;
    _lagDetector.stop();
    _devBridge?.stop();
  }

  /// Limpa o histórico de métricas acumulado e o histórico de rotas.
  void clearHistory() {
    _history.clear();
    _routeHistory.clear();
  }

  void _onReportTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameTimings.addLast(timing);
      if (_frameTimings.length > windowFrameSize) {
        _frameTimings.removeFirst();
      }
    }
  }

  void _computeMetrics() {
    final now = DateTime.now();

    // 1. Rota Atual e Rebuilds
    final currentRoute = PerformanceRouteObserver().currentRoute;
    final totalRebuilds = PerformanceRebuildTracker().totalRebuilds;

    // 2. Memória RAM, Taxa ΔRAM e ΔRota
    final platformMemory = getPlatformMemoryMb();
    final double currentMemoryMb = platformMemory ?? -1.0;
    double deltaMemoryMb = 0.0;
    if (platformMemory != null) {
      // Rastreamento por rota e tempo de carga da tela
      if (currentRoute != _lastObservedRoute) {
        if (_lastObservedRoute.isNotEmpty) {
          // ponytail: mantém buffer circular com as últimas 10 rotas para auditoria sem inflar memória
          _routeHistory.add(
            RouteHistoryEntry(
              route: _lastObservedRoute,
              mountDurationMs: _routeMountDurationMs,
              deltaMemoryMb: _routeDeltaMemoryMb,
              worstFrameMs: _worstFrameInCurrentRoute,
              timestamp: now,
            ),
          );
          if (_routeHistory.length > 10) {
            _routeHistory.removeAt(0);
          }
        }
        _lastObservedRoute = currentRoute;
        _memoryOnRouteEntryMb = currentMemoryMb;
        _routeDeltaMemoryMb = 0.0;
        _routeEnteredAt = now;
        _routeMountDurationMs = 0.0;
        _worstFrameInCurrentRoute = 0.0;
      } else {
        if (_memoryOnRouteEntryMb >= 0) {
          _routeDeltaMemoryMb = currentMemoryMb - _memoryOnRouteEntryMb;
        }
        if (_routeEnteredAt != null && _routeMountDurationMs == 0.0) {
          _routeMountDurationMs = now.difference(_routeEnteredAt!).inMilliseconds.toDouble();
        }
      }

      // Cálculo de taxa instantânea (MB/s) com deadband e decaimento
      if (_previousMemoryRssMb > 0 && _lastMemorySampleTime != null) {
        final elapsedSec = now.difference(_lastMemorySampleTime!).inMilliseconds / 1000.0;
        if (elapsedSec > 0) {
          final rawRate = (currentMemoryMb - _previousMemoryRssMb) / elapsedSec;
          // ponytail: deadband de 0.1 MB/s para eliminar jitter natural de GC
          final instantRate = rawRate.abs() < 0.1 ? 0.0 : rawRate;

          if (instantRate.abs() >= _decayingDeltaRate.abs()) {
            _decayingDeltaRate = instantRate;
          } else {
            _decayingDeltaRate *= 0.7;
            if (_decayingDeltaRate.abs() < 0.05) _decayingDeltaRate = 0.0;
          }
          deltaMemoryMb = _decayingDeltaRate;
        }
      }
      _lastMemorySampleTime = now;
      _previousMemoryRssMb = currentMemoryMb;

      if (currentMemoryMb > _peakMemoryRssMb) {
        _peakMemoryRssMb = currentMemoryMb;
      }
    }

    // 3. Se não houver frames registrados ainda
    if (_frameTimings.isEmpty) {
      _lastData = _lastData.copyWith(
        memoryRssMb: currentMemoryMb,
        deltaMemoryRssMb: deltaMemoryMb,
        routeDeltaMemoryMb: _routeDeltaMemoryMb,
        peakMemoryRssMb: _peakMemoryRssMb,
        eventLoopLagMs: _lagDetector.currentLagMs,
        currentRoute: currentRoute,
        rebuildCount: totalRebuilds,
        routeHistory: List.unmodifiable(_routeHistory),
        timestamp: now,
      );
      _history.add(_lastData);
      return;
    }

    // 4. Cálculo de FPS instantâneo a partir do último frame
    final lastTiming = _frameTimings.last;
    final lastDurationInMs = lastTiming.totalSpan.inMicroseconds / 1000.0;
    final currentFps = lastDurationInMs > 0
        ? (1000.0 / lastDurationInMs).clamp(0.0, 120.0)
        : 60.0;

    // 5. Médias na janela deslizante
    double totalTotalMs = 0;
    double totalUiMs = 0;
    double totalRasterMs = 0;
    double worstFrameMs = 0;
    int jankCount = 0;

    for (final timing in _frameTimings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
      final uiMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;

      totalTotalMs += totalMs;
      totalUiMs += uiMs;
      totalRasterMs += rasterMs;

      if (totalMs > worstFrameMs) {
        worstFrameMs = totalMs;
      }

      if (totalMs > _worstFrameInCurrentRoute) {
        _worstFrameInCurrentRoute = totalMs;
      }

      if (totalMs > jankThresholdMs) {
        jankCount++;
      }
    }

    final frameCount = _frameTimings.length;
    final avgTotalMs = totalTotalMs / frameCount;
    final avgFps = avgTotalMs > 0 ? (1000.0 / avgTotalMs).clamp(0.0, 120.0) : 60.0;
    final avgUiMs = totalUiMs / frameCount;
    final avgRasterMs = totalRasterMs / frameCount;
    final jankPercentage = (jankCount / frameCount) * 100.0;

    _lastData = PerformanceData(
      currentFps: currentFps,
      averageFps: avgFps,
      uiDurationMs: avgUiMs,
      rasterDurationMs: avgRasterMs,
      jankPercentage: jankPercentage,
      worstFrameMs: worstFrameMs,
      memoryRssMb: currentMemoryMb,
      deltaMemoryRssMb: deltaMemoryMb,
      routeDeltaMemoryMb: _routeDeltaMemoryMb,
      peakMemoryRssMb: _peakMemoryRssMb,
      eventLoopLagMs: _lagDetector.currentLagMs,
      currentRoute: currentRoute,
      rebuildCount: totalRebuilds,
      httpLatencyMs: PerformanceNetworkTracker().averageLatencyMs,
      routeMountDurationMs: _routeMountDurationMs,
      routeHistory: List.unmodifiable(_routeHistory),
      timestamp: now,
    );

    _history.add(_lastData);
    if (_history.length > 200) {
      _history.removeAt(0);
    }
  }

  Future<void> _exportMetricsToFile() async {
    if (kIsWeb || _history.isEmpty || exportFilePath == null) return;

    try {
      final file = File(exportFilePath!);
      final dataToExport = _history.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode(dataToExport);

      await file.writeAsString(jsonString, mode: FileMode.write, flush: true);
    } catch (_) {}
  }

  /// Limpa recursos e remove os callbacks do Flutter engine.
  void dispose() {
    stop();
    _frameTimings.clear();
    _history.clear();
    _serviceExtensions?.unregister();
    _devBridge?.dispose();
  }
}
