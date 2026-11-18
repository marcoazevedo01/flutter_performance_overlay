import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceData Tests', () {
    test('PerformanceData.initial() returns default values including new metrics', () {
      final data = PerformanceData.initial();
      expect(data.currentFps, 60.0);
      expect(data.averageFps, 60.0);
      expect(data.uiDurationMs, 0.0);
      expect(data.rasterDurationMs, 0.0);
      expect(data.jankPercentage, 0.0);
      expect(data.worstFrameMs, 16.6);
      expect(data.memoryRssMb, 0.0);
      expect(data.deltaMemoryRssMb, 0.0);
      expect(data.routeDeltaMemoryMb, 0.0);
      expect(data.sessionDeltaMemoryMb, 0.0);
      expect(data.peakMemoryRssMb, 0.0);
      expect(data.eventLoopLagMs, 0.0);
      expect(data.currentRoute, '/');
      expect(data.rebuildCount, 0);
      expect(data.routeMountDurationMs, 0.0);
      expect(data.routeHistory, isEmpty);
    });

    test('PerformanceData.toJson() formats all metrics correctly', () {
      final data = PerformanceData(
        currentFps: 59.876,
        averageFps: 58.123,
        uiDurationMs: 4.567,
        rasterDurationMs: 7.891,
        jankPercentage: 2.345,
        worstFrameMs: 22.1,
        memoryRssMb: 45.678,
        deltaMemoryRssMb: 1.234,
        routeDeltaMemoryMb: 5.678,
        sessionDeltaMemoryMb: 18.456,
        peakMemoryRssMb: 80.123,
        eventLoopLagMs: 12.34,
        currentRoute: '/detalhes',
        rebuildCount: 42,
        timestamp: DateTime(2026, 8, 25, 12, 0, 0),
      );

      final json = data.toJson();
      expect(json['currentFps'], 59.9);
      expect(json['averageFps'], 58.1);
      expect(json['uiDurationMs'], 4.57);
      expect(json['rasterDurationMs'], 7.89);
      expect(json['jankPercentage'], 2.3);
      expect(json['worstFrameMs'], 22.1);
      expect(json['memoryRssMb'], 45.68);
      expect(json['deltaMemoryRssMb'], 1.23);
      expect(json['routeDeltaMemoryMb'], 5.68);
      expect(json['sessionDeltaMemoryMb'], 18.46);
      expect(json['peakMemoryRssMb'], 80.12);
      expect(json['eventLoopLagMs'], 12.3);
      expect(json['currentRoute'], '/detalhes');
      expect(json['rebuildCount'], 42);
      expect(json['routeMountDurationMs'], 0.0);
      expect(json['routeHistory'], isEmpty);
    });

    test('RouteHistoryEntry formats properly to JSON', () {
      final entry = RouteHistoryEntry(
        route: '/produtos',
        mountDurationMs: 450.5,
        deltaMemoryMb: 12.34,
        worstFrameMs: 28.5,
        timestamp: DateTime(2026, 10, 24, 14, 0, 0),
      );

      final json = entry.toJson();
      expect(json['route'], '/produtos');
      expect(json['mountDurationMs'], 450.5);
      expect(json['deltaMemoryMb'], 12.34);
      expect(json['worstFrameMs'], 28.5);
    });

    test('PerformanceDiagnostics alerts on critical memory (> 1000MB)', () {
      final data = PerformanceData.initial().copyWith(
        memoryRssMb: 1200.0,
        peakMemoryRssMb: 1500.0,
      );

      final issues = PerformanceDiagnostics.analyze(
        currentData: data,
        history: [data],
      );

      final oomIssue = issues.firstWhere((i) => i.title.contains('Risco de OOM'));
      expect(oomIssue.severity, DiagnosticSeverity.warning);
      expect(oomIssue.description.contains('1200.0MB'), true);
    });

    test('PerformanceData.copyWith() updates new metrics properly', () {
      final initial = PerformanceData.initial();
      final updated = initial.copyWith(
        currentFps: 45.0,
        memoryRssMb: 100.5,
        deltaMemoryRssMb: 2.5,
        sessionDeltaMemoryMb: 35.5,
        currentRoute: '/login',
        rebuildCount: 10,
      );

      expect(updated.currentFps, 45.0);
      expect(updated.memoryRssMb, 100.5);
      expect(updated.deltaMemoryRssMb, 2.5);
      expect(updated.sessionDeltaMemoryMb, 35.5);
      expect(updated.currentRoute, '/login');
      expect(updated.rebuildCount, 10);
      expect(updated.averageFps, initial.averageFps);
    });
  });

  group('PerformanceRouteObserver Tests', () {
    test('Track and notify route changes', () async {
      final observer = PerformanceRouteObserver();
      expect(observer.currentRoute, '/');

      final futureRoute = observer.routeStream.first;
      observer.setCurrentRoute('/pedidos');

      expect(observer.currentRoute, '/pedidos');
      expect(await futureRoute, '/pedidos');
    });
  });

  group('PerformanceRebuildTracker Tests', () {
    test('Record rebuilds and reset', () {
      final tracker = PerformanceRebuildTracker();
      tracker.reset();
      expect(tracker.totalRebuilds, 0);

      tracker.recordRebuild('ItemWidget');
      tracker.recordRebuild('ItemWidget');
      tracker.recordRebuild('HeaderWidget');

      expect(tracker.totalRebuilds, 3);
      expect(tracker.rebuildsByWidget['ItemWidget'], 2);
      expect(tracker.rebuildsByWidget['HeaderWidget'], 1);

      tracker.reset();
      expect(tracker.totalRebuilds, 0);
      expect(tracker.rebuildsByWidget.isEmpty, true);
    });
  });

  group('PerformanceOverlayConfig Tests', () {
    test('Default config has expected defaults', () {
      const config = PerformanceOverlayConfig();
      expect(config.enabled, true);
      expect(config.showFps, true);
      expect(config.showUiRasterTiming, true);
      expect(config.showJankRate, true);
      expect(config.showMemory, true);
      expect(config.showDeltaMemory, true);
      expect(config.showRouteDeltaMemory, true);
      expect(config.showPeakMemory, true);
      expect(config.showEventLoopLag, true);
      expect(config.showCurrentRoute, true);
      expect(config.showRebuildCount, true);
      expect(config.keepWithinSafeArea, true);
      expect(config.startExpanded, false);
      expect(config.goodFpsThreshold, 55.0);
      expect(config.warningFpsThreshold, 30.0);
    });
  });

  group('Remote Streaming & Log/Error Capture Tests', () {
    test('startStreaming captures logs, errors, and samples, drains between chunks, and restores handlers on stopStreaming', () async {
      final originalDebugPrint = debugPrint;
      final originalFlutterError = FlutterError.onError;
      final originalPlatformError = PlatformDispatcher.instance.onError;

      final List<String?> forwardedLogs = [];
      final List<FlutterErrorDetails> forwardedErrors = [];

      debugPrint = (String? message, {int? wrapWidth}) {
        forwardedLogs.add(message);
      };
      FlutterError.onError = (FlutterErrorDetails details) {
        forwardedErrors.add(details);
      };

      final stubDebugPrint = debugPrint;
      final stubFlutterError = FlutterError.onError;

      final service = PerformanceMonitorService(
        enableDevBridge: false,
        refreshInterval: const Duration(milliseconds: 20),
        appName: 'SupraHelpTest',
      );

      addTearDown(() {
        service.dispose();
        debugPrint = originalDebugPrint;
        FlutterError.onError = originalFlutterError;
        PlatformDispatcher.instance.onError = originalPlatformError;
      });

      final chunks = <Map<String, dynamic>>[];
      final twoChunksCompleter = Completer<void>();

      service.startStreaming(
        interval: const Duration(milliseconds: 40),
        captureLogs: true,
        captureErrors: true,
        onChunk: (chunk) {
          chunks.add(chunk);
          if (chunks.length >= 2 && !twoChunksCompleter.isCompleted) {
            twoChunksCompleter.complete();
          }
        },
      );

      expect(service.isStreaming, isTrue);

      debugPrint('Log de teste 1');
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('Erro de teste 1')),
      );

      await twoChunksCompleter.future.timeout(const Duration(seconds: 2));

      expect(chunks.length, greaterThanOrEqualTo(2));

      final firstChunk = chunks[0];
      expect(firstChunk['timestamp'], isA<String>());
      expect(firstChunk['appName'], 'SupraHelpTest');
      expect(firstChunk['instanceId'], service.instanceId);
      expect(firstChunk['currentMetrics'], isA<Map<String, dynamic>>());
      expect(firstChunk['samples'], isA<List>());
      expect((firstChunk['samples'] as List), isNotEmpty);
      expect(firstChunk['diagnostics'], isA<List>());
      expect(firstChunk['rebuilds'], isA<Map<String, dynamic>>());

      final firstLogs = firstChunk['logs'] as List;
      final firstErrors = firstChunk['errors'] as List;
      expect(
        firstLogs.any((l) => (l as Map)['message'] == 'Log de teste 1'),
        isTrue,
      );
      expect(
        firstErrors.any((e) => (e as Map)['error'].toString().contains('Erro de teste 1')),
        isTrue,
      );
      expect(forwardedLogs, contains('Log de teste 1'));
      expect(
        forwardedErrors.any((d) => d.exception.toString().contains('Erro de teste 1')),
        isTrue,
      );

      // Segundo chunk deve ter logs e erros drenados (vazios)
      final secondChunk = chunks[1];
      expect((secondChunk['logs'] as List), isEmpty);
      expect((secondChunk['errors'] as List), isEmpty);

      // Dupla chamada de startStreaming não deve criar loop nem perder referência original
      final secondStreamChunks = <Map<String, dynamic>>[];
      service.startStreaming(
        interval: const Duration(milliseconds: 50),
        captureLogs: true,
        captureErrors: true,
        onChunk: secondStreamChunks.add,
      );

      debugPrint('Log apos reinicio');
      expect(forwardedLogs.where((m) => m == 'Log apos reinicio').length, 1);

      final finalChunk = service.stopStreaming();
      expect(service.isStreaming, isFalse);
      expect(
        (finalChunk['logs'] as List).any((l) => (l as Map)['message'] == 'Log apos reinicio'),
        isTrue,
      );

      // Handlers restaurados exatamente para as referências originais
      expect(identical(debugPrint, stubDebugPrint), isTrue);
      expect(identical(FlutterError.onError, stubFlutterError), isTrue);
      expect(identical(PlatformDispatcher.instance.onError, originalPlatformError), isTrue);
    });

    test('Process baseline memory persists across Hot Restart simulation and resets on clearHistory', () {
      addTearDown(() => resetProcessBaselineMemoryMb());

      resetProcessBaselineMemoryMb(100.0);
      expect(getOrSetProcessBaselineMemoryMb(140.0), 100.0);

      resetProcessBaselineMemoryMb(140.0);
      expect(getOrSetProcessBaselineMemoryMb(150.0), 140.0);

      final service = PerformanceMonitorService(enableDevBridge: false);
      addTearDown(service.dispose);
      resetProcessBaselineMemoryMb(1.0);
      service.clearHistory();
      if (getPlatformMemoryMb() != null) {
        final afterClear = getOrSetProcessBaselineMemoryMb(999.0);
        expect(afterClear, isNot(1.0));
        expect(afterClear, isNot(999.0));
      }
    });

    test('PerformanceRemoteRelay buffers chunks during disconnect and flushes on reconnect', () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final statuses = <RelayConnectionStatus>[];
      final receivedOnReconnect = <Map<String, dynamic>>[];
      final reconnectFlushed = Completer<void>();
      final firstRegistered = Completer<void>();
      int connectionCount = 0;

      server.listen((req) async {
        if (!WebSocketTransformer.isUpgradeRequest(req)) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        connectionCount++;
        final currentConn = connectionCount;

        ws.listen((raw) async {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (currentConn == 1 && msg['type'] == 'register') {
            ws.add(jsonEncode({
              'type': 'start',
              'requesterId': 'r1',
              'intervalSec': 1,
            }));
            if (!firstRegistered.isCompleted) firstRegistered.complete();
            await Future.delayed(const Duration(milliseconds: 50));
            await ws.close();
          } else if (currentConn >= 2) {
            receivedOnReconnect.add(msg);
            if (msg['type'] == 'chunk' && !reconnectFlushed.isCompleted) {
              reconnectFlushed.complete();
            }
          }
        });
      });

      final originalDebugPrint = debugPrint;
      final service = PerformanceMonitorService(
        enableDevBridge: false,
        enableServiceExtensions: false,
        refreshInterval: const Duration(milliseconds: 25),
      );

      final relay = PerformanceRemoteRelay(
        relayUrl: 'ws://127.0.0.1:${server.port}/perf-ws',
        relayKey: 'k1',
        monitorService: service,
        reconnectDelay: const Duration(milliseconds: 1250),
        onStatusChanged: statuses.add,
      );

      addTearDown(() async {
        relay.dispose();
        service.dispose();
        await server.close(force: true);
        debugPrint = originalDebugPrint;
        HttpOverrides.global = prevOverrides;
      });

      relay.connect();
      await firstRegistered.future.timeout(const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: 100));

      // Gera log enquanto o relay está desconectado aguardando reconnectDelay
      debugPrint('Log durante queda 4G');

      await reconnectFlushed.future.timeout(const Duration(seconds: 5));

      expect(statuses, contains(RelayConnectionStatus.reconnecting));
      expect(statuses.last, RelayConnectionStatus.connected);
      expect(
        receivedOnReconnect.any((m) => m['type'] == 'register'),
        isTrue,
      );
      final flushedChunk = receivedOnReconnect.firstWhere((m) => m['type'] == 'chunk');
      final logs = (flushedChunk['chunk'] as Map)['logs'] as List;
      expect(
        logs.any((l) => (l as Map)['message'] == 'Log durante queda 4G'),
        isTrue,
      );
    });
  });
}
