import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show File, FileMode;
import 'dart:ui' show ErrorCallback, PlatformDispatcher;
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
import 'remote_relay/remote_relay.dart';
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

  /// Nome da aplicação que hospeda o monitor (útil em painéis multi-app).
  final String appName;

  /// Identificador único desta instância em execução.
  late final String instanceId;

  /// Nome opcional do usuário ativo no aplicativo.
  final String? userName;

  /// Nome opcional do dispositivo.
  final String? deviceName;

  /// Versão opcional do aplicativo hospedeiro.
  final String? appVersion;

  /// URL WebSocket opcional de relay remoto privado.
  final String? remoteRelayUrl;

  /// Chave de autenticação opcional para o relay remoto.
  final String? remoteRelayKey;

  /// Se deve redigir tokens, senhas e documentos em logs/erros antes de armazenar no chunk.
  final bool sanitizeLogs;

  String? _detectedAppName;
  String? _detectedAppVersion;
  String? _detectedUserName;
  String? _dynamicUserName;
  String? _dynamicAppVersion;
  bool _disposed = false;

  String get effectiveAppName => (appName != 'FlutterApp' && appName.isNotEmpty)
      ? appName
      : (_detectedAppName ?? getPlatformAppName());

  String get effectiveDeviceName =>
      (deviceName != null && deviceName!.isNotEmpty) ? deviceName! : getPlatformDeviceName();

  String get effectiveAppVersion {
    final custom = _dynamicAppVersion ?? appVersion;
    if (custom != null && custom.isNotEmpty) return custom;
    return _detectedAppVersion ?? '1.0.0';
  }

  String? get effectiveUserName {
    final custom = _dynamicUserName ?? userName;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return _detectedUserName;
  }

  final Queue<FrameTiming> _frameTimings = Queue<FrameTiming>();
  final List<PerformanceData> _history = [];

  Timer? _exportTimer;
  Timer? _uiRefreshTimer;
  Timer? _streamTimer;
  late final EventLoopLagDetector _lagDetector;
  PerformanceDevBridge? _devBridge;
  PerformanceServiceExtensions? _serviceExtensions;
  PerformanceRemoteRelay? _remoteRelay;

  bool _startedByStreaming = false;
  bool _hooksInstalled = false;
  bool _logsHooked = false;
  bool _errorsHooked = false;
  bool _inDebugPrint = false;
  DebugPrintCallback? _originalDebugPrint;
  DebugPrintCallback? _installedDebugPrint;
  FlutterExceptionHandler? _originalFlutterError;
  FlutterExceptionHandler? _installedFlutterError;
  ErrorCallback? _originalPlatformError;
  ErrorCallback? _installedPlatformError;
  final List<PerformanceData> _pendingSamples = [];
  final List<Map<String, dynamic>> _capturedLogs = [];
  final List<Map<String, dynamic>> _capturedErrors = [];

  double _previousMemoryRssMb = 0.0;
  double _peakMemoryRssMb = 0.0;
  DateTime? _lastMemorySampleTime;
  double _decayingDeltaRate = 0.0;
  String _lastObservedRoute = '';
  double _memoryOnRouteEntryMb = -1.0;
  double _routeDeltaMemoryMb = 0.0;
  double _sessionDeltaMemoryMb = 0.0;
  DateTime? _routeEnteredAt;
  double _routeMountDurationMs = 0.0;
  double _worstFrameInCurrentRoute = 0.0;
  final List<RouteHistoryEntry> _routeHistory = [];
  bool _isRunning = false;

  /// Indica se há uma sessão de streaming remoto ativa.
  bool get isStreaming => _streamTimer != null;

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
    this.enableDevBridge = kDebugMode,
    this.enableServiceExtensions = true,
    this.devBridgePort = 8765,
    this.appName = 'FlutterApp',
    String? instanceId,
    this.userName,
    this.deviceName,
    this.appVersion,
    this.remoteRelayUrl,
    this.remoteRelayKey,
    this.sanitizeLogs = true,
  }) {
    this.instanceId = instanceId ??
        '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';
    _lagDetector = EventLoopLagDetector(
      interval: const Duration(milliseconds: 200),
    );

    if (enableDevBridge && !kIsWeb) {
      _devBridge = PerformanceDevBridge(
        port: devBridgePort,
        monitorService: this,
      )..start();
    }

    if (enableServiceExtensions && !kIsWeb) {
      _serviceExtensions = PerformanceServiceExtensions(
        monitorService: this,
      );
    }

    if (remoteRelayUrl != null && remoteRelayUrl!.isNotEmpty) {
      _remoteRelay = PerformanceRemoteRelay(
        relayUrl: remoteRelayUrl!,
        relayKey: remoteRelayKey,
        monitorService: this,
      )..connect();
    }

    unawaited(_detectPlatformMetadata());
  }

  Future<void> _detectPlatformMetadata() async {
    final meta = await getPlatformAppMetadata();
    if (_disposed) return;

    bool changed = false;
    final name = meta['appName'];
    final ver = meta['appVersion'];
    final user = meta['userName'];

    if (name != null && name.isNotEmpty && _detectedAppName != name) {
      _detectedAppName = name;
      changed = true;
    }
    if (ver != null && ver.isNotEmpty && _detectedAppVersion != ver) {
      _detectedAppVersion = ver;
      changed = true;
    }
    if (user != null && user.isNotEmpty && _detectedUserName != user) {
      _detectedUserName = user;
      changed = true;
    }

    if (changed) {
      _remoteRelay?.refreshRegistration();
    }
  }

  /// Atualiza metadados dinâmicos (ex: usuário após login) e reenvia registro ao relay.
  void updateMetadata({String? userName, String? appVersion}) {
    bool changed = false;
    if (userName != null && userName != _dynamicUserName) {
      _dynamicUserName = userName;
      changed = true;
    }
    if (appVersion != null && appVersion != _dynamicAppVersion) {
      _dynamicAppVersion = appVersion;
      changed = true;
    }
    if (changed) {
      _remoteRelay?.refreshRegistration();
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
    _installHooks(captureLogs: true, captureErrors: true);

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

    _streamTimer?.cancel();
    _streamTimer = null;
    _startedByStreaming = false;
    _restoreHooks();

    SchedulerBinding.instance.removeTimingsCallback(_onReportTimings);
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
    _exportTimer?.cancel();
    _exportTimer = null;
    _lagDetector.stop();
    _devBridge?.stop();
  }

  /// Inicia o streaming contínuo de métricas, diagnósticos, logs e erros em background.
  void startStreaming({
    Duration interval = const Duration(seconds: 5),
    bool captureLogs = true,
    bool captureErrors = true,
    required void Function(Map<String, dynamic> chunk) onChunk,
  }) {
    if (isStreaming) {
      _streamTimer?.cancel();
      _streamTimer = null;
      _restoreHooks();
    }

    _pendingSamples.clear();
    if (!_isRunning) {
      _capturedLogs.clear();
      _capturedErrors.clear();
      _startedByStreaming = true;
      start();
    }

    _installHooks(captureLogs: captureLogs, captureErrors: captureErrors);

    _streamTimer = Timer.periodic(interval, (_) {
      onChunk(_buildAndDrainChunk());
    });
  }

  /// Encerra o streaming contínuo, restaura handlers se iniciado pelo stream e retorna o último lote coletado.
  Map<String, dynamic> stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;

    final finalChunk = _buildAndDrainChunk();

    if (_startedByStreaming) {
      _startedByStreaming = false;
      stop();
    } else if (_isRunning) {
      _installHooks(captureLogs: true, captureErrors: true);
    } else {
      _restoreHooks();
    }

    return finalChunk;
  }

  /// Limpa o histórico de métricas acumulado e o histórico de rotas.
  void clearHistory() {
    _history.clear();
    _routeHistory.clear();
    final currentMem = getPlatformMemoryMb();
    resetProcessBaselineMemoryMb(currentMem);
    _sessionDeltaMemoryMb = 0.0;
    if (currentMem != null) {
      _memoryOnRouteEntryMb = currentMem;
      _routeDeltaMemoryMb = 0.0;
    }
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
      final baselineMb = getOrSetProcessBaselineMemoryMb(currentMemoryMb);
      _sessionDeltaMemoryMb = currentMemoryMb - baselineMb;

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
        sessionDeltaMemoryMb: _sessionDeltaMemoryMb,
        peakMemoryRssMb: _peakMemoryRssMb,
        eventLoopLagMs: _lagDetector.currentLagMs,
        currentRoute: currentRoute,
        rebuildCount: totalRebuilds,
        routeHistory: List.unmodifiable(_routeHistory),
        timestamp: now,
      );
      _recordSample(_lastData);
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
      sessionDeltaMemoryMb: _sessionDeltaMemoryMb,
      peakMemoryRssMb: _peakMemoryRssMb,
      eventLoopLagMs: _lagDetector.currentLagMs,
      currentRoute: currentRoute,
      rebuildCount: totalRebuilds,
      httpLatencyMs: PerformanceNetworkTracker().averageLatencyMs,
      routeMountDurationMs: _routeMountDurationMs,
      routeHistory: List.unmodifiable(_routeHistory),
      timestamp: now,
    );

    _recordSample(_lastData);
  }

  void _recordSample(PerformanceData data) {
    _history.add(data);
    if (_history.length > 200) {
      _history.removeAt(0);
    }

    if (isStreaming) {
      _pendingSamples.add(data);
      // ponytail: limite de 120 amostras por lote para proteger memória
      if (_pendingSamples.length > 120) {
        _pendingSamples.removeAt(0);
      }
    }
  }

  static final _reBearer = RegExp(
    r'Bearer\s+[A-Za-z0-9\-._~+/]+=*',
    caseSensitive: false,
  );
  static final _reAuthHeader = RegExp(
    r'(authorization\s*[:=]\s*(?:basic\s+|bearer\s+)?)([^\s,;}\x22\x27]+)',
    caseSensitive: false,
  );
  static final _reQuotedSecret = RegExp(
    r'([\x22\x27](?:access_?token|refresh_?token|auth_?token|token|senha|password|secret|api_?key|x-perf-key)[\x22\x27]\s*:\s*[\x22\x27])([^\x22\x27]*)([\x22\x27])',
    caseSensitive: false,
  );
  static final _rePlainSecret = RegExp(
    r'(\b(?:access_?token|refresh_?token|auth_?token|token|senha|password|secret|api_?key|x-perf-key)\s*[:=]\s*)(?!\[REDACTED)(?![\x22\x27])([^\s,;\}\]\x22\x27]+)',
    caseSensitive: false,
  );

  /// Redige tokens e senhas (quando [redact] é true) e trunca mensagens longas para envio seguro.
  @visibleForTesting
  static String sanitizeText(String input, {bool redact = true}) {
    var out = input;
    if (redact) {
      out = out.replaceAll(_reBearer, 'Bearer [REDACTED]');
      out = out.replaceAllMapped(_reAuthHeader, (m) => '${m[1]}[REDACTED]');
      out = out.replaceAllMapped(_reQuotedSecret, (m) => '${m[1]}[REDACTED]${m[3]}');
      out = out.replaceAllMapped(_rePlainSecret, (m) => '${m[1]}[REDACTED]');
    }
    if (out.length > 8192) {
      out = '${out.substring(0, 8192)}... [truncated]';
    }
    return out;
  }

  /// Registra manualmente uma mensagem de log no buffer circular do serviço.
  void recordLog(String message) {
    // ponytail: limite de 200 logs por chunk para evitar OOM
    if (_capturedLogs.length >= 200) {
      _capturedLogs.removeAt(0);
    }
    _capturedLogs.add({
      'timestamp': DateTime.now().toIso8601String(),
      'route': PerformanceRouteObserver().currentRoute,
      'message': sanitizeText(message, redact: sanitizeLogs),
    });
  }

  /// Especificação de Zone para capturar chamadas diretas a `print()` sem duplicar `debugPrint()`.
  ZoneSpecification get logZoneSpecification => ZoneSpecification(
        print: (self, parent, zone, line) {
          if (_logsHooked && !_inDebugPrint) {
            recordLog(line);
          }
          parent.print(zone, line);
        },
      );

  /// Executa [body] em uma Zone que também captura chamadas diretas a `print()`.
  R runZonedWithLogCapture<R>(R Function() body) {
    return runZoned(body, zoneSpecification: logZoneSpecification);
  }

  void _installHooks({required bool captureLogs, required bool captureErrors}) {
    if (_hooksInstalled) {
      _restoreHooks();
    }

    if (captureLogs) {
      final previousDebugPrint = debugPrint;
      _originalDebugPrint = previousDebugPrint;
      _logsHooked = true;
      late final DebugPrintCallback wrapper;
      wrapper = (String? message, {int? wrapWidth}) {
        if (_logsHooked && message != null) {
          recordLog(message);
        }
        _inDebugPrint = true;
        try {
          previousDebugPrint(message, wrapWidth: wrapWidth);
        } finally {
          _inDebugPrint = false;
        }
      };
      _installedDebugPrint = wrapper;
      debugPrint = wrapper;
    }

    if (captureErrors) {
      final previousFlutterError = FlutterError.onError;
      final previousPlatformError = PlatformDispatcher.instance.onError;
      _originalFlutterError = previousFlutterError;
      _originalPlatformError = previousPlatformError;
      _errorsHooked = true;

      late final FlutterExceptionHandler flutterWrapper;
      flutterWrapper = (FlutterErrorDetails details) {
        if (_errorsHooked) {
          _appendError(
            details.exceptionAsString(),
            details.stack?.toString() ?? '',
          );
        }
        previousFlutterError?.call(details);
      };
      _installedFlutterError = flutterWrapper;
      FlutterError.onError = flutterWrapper;

      late final ErrorCallback platformWrapper;
      platformWrapper = (Object error, StackTrace stack) {
        if (_errorsHooked) {
          _appendError(error.toString(), stack.toString());
        }
        return previousPlatformError?.call(error, stack) ?? false;
      };
      _installedPlatformError = platformWrapper;
      PlatformDispatcher.instance.onError = platformWrapper;
    }

    _hooksInstalled = _logsHooked || _errorsHooked;
  }

  void _appendError(String error, String stackTrace) {
    // ponytail: limite de 50 erros por chunk para evitar OOM
    if (_capturedErrors.length >= 50) {
      _capturedErrors.removeAt(0);
    }
    _capturedErrors.add({
      'timestamp': DateTime.now().toIso8601String(),
      'route': PerformanceRouteObserver().currentRoute,
      'error': sanitizeText(error, redact: sanitizeLogs),
      'stackTrace': sanitizeText(stackTrace, redact: sanitizeLogs),
    });
  }

  void _restoreHooks() {
    if (!_hooksInstalled) return;

    if (_logsHooked) {
      if (identical(debugPrint, _installedDebugPrint) && _originalDebugPrint != null) {
        debugPrint = _originalDebugPrint!;
      }
      _originalDebugPrint = null;
      _installedDebugPrint = null;
      _logsHooked = false;
    }

    if (_errorsHooked) {
      if (identical(FlutterError.onError, _installedFlutterError)) {
        FlutterError.onError = _originalFlutterError;
      }
      if (identical(PlatformDispatcher.instance.onError, _installedPlatformError)) {
        PlatformDispatcher.instance.onError = _originalPlatformError;
      }
      _originalFlutterError = null;
      _installedFlutterError = null;
      _originalPlatformError = null;
      _installedPlatformError = null;
      _errorsHooked = false;
    }

    _hooksInstalled = false;
  }

  /// Constrói e drena um chunk sob demanda (usado pelo bridge local/streaming).
  Map<String, dynamic> buildCurrentChunk() => _buildAndDrainChunk();

  Map<String, dynamic> _buildAndDrainChunk() {
    if (_pendingSamples.isEmpty) {
      _computeMetrics();
      if (_pendingSamples.isEmpty) {
        _pendingSamples.add(_lastData);
      }
    }

    final chunk = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'appName': effectiveAppName,
      'instanceId': instanceId,
      'currentMetrics': _lastData.toJson(),
      'samples': _pendingSamples.map((e) => e.toJson()).toList(),
      'diagnostics': PerformanceDiagnostics.analyze(
        currentData: _lastData,
        history: _history,
      ).map((e) => e.toJson()).toList(),
      'rebuilds': PerformanceRebuildTracker().rebuildsByWidget,
      'logs': List<Map<String, dynamic>>.from(_capturedLogs),
      'errors': List<Map<String, dynamic>>.from(_capturedErrors),
    };

    _pendingSamples.clear();
    _capturedLogs.clear();
    _capturedErrors.clear();

    return chunk;
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
    _disposed = true;
    stop();
    _frameTimings.clear();
    _history.clear();
    _serviceExtensions?.unregister();
    _remoteRelay?.dispose();
    _devBridge?.dispose();
  }
}
