import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceDiagnostics Tests', () {
    test('Identifies low FPS and high Jank issues', () {
      final badData = PerformanceData(
        currentFps: 20.0,
        averageFps: 24.0,
        uiDurationMs: 4.0,
        rasterDurationMs: 6.0,
        jankPercentage: 25.0,
        worstFrameMs: 50.0,
        memoryRssMb: 50.0,
        deltaMemoryRssMb: 0.1,
        peakMemoryRssMb: 60.0,
        eventLoopLagMs: 0.0,
        currentRoute: '/catalogo',
        rebuildCount: 10,
        timestamp: DateTime.now(),
      );

      final issues = PerformanceDiagnostics.analyze(
        currentData: badData,
        history: [badData],
      );

      expect(issues.any((i) => i.title.contains('Baixa Taxa de Quadros')), isTrue);
      expect(issues.any((i) => i.title.contains('Taxa Excessiva de Frames Perdidos')), isTrue);
    });

    test('Identifies UI thread bottleneck and Event Loop Lag', () {
      final frozenData = PerformanceData(
        currentFps: 58.0,
        averageFps: 58.0,
        uiDurationMs: 18.5,
        rasterDurationMs: 5.0,
        jankPercentage: 2.0,
        worstFrameMs: 20.0,
        memoryRssMb: 50.0,
        deltaMemoryRssMb: 0.0,
        peakMemoryRssMb: 50.0,
        eventLoopLagMs: 120.0,
        currentRoute: '/login',
        rebuildCount: 5,
        timestamp: DateTime.now(),
      );

      final issues = PerformanceDiagnostics.analyze(
        currentData: frozenData,
        history: [frozenData],
      );

      expect(issues.any((i) => i.title.contains('Gargalo na UI Thread')), isTrue);
      expect(issues.any((i) => i.title.contains('Bloqueio Síncrono no Event Loop')), isTrue);
    });

    test('Identifies high Delta RAM and Rebuild Hotspots', () {
      final leakData = PerformanceData(
        currentFps: 60.0,
        averageFps: 60.0,
        uiDurationMs: 4.0,
        rasterDurationMs: 4.0,
        jankPercentage: 0.0,
        worstFrameMs: 16.0,
        memoryRssMb: 120.0,
        deltaMemoryRssMb: 8.5,
        routeDeltaMemoryMb: 20.0,
        peakMemoryRssMb: 120.0,
        eventLoopLagMs: 0.0,
        currentRoute: '/relatorio',
        rebuildCount: 200,
        timestamp: DateTime.now(),
      );

      final issues = PerformanceDiagnostics.analyze(
        currentData: leakData,
        history: [leakData],
        rebuildsByWidget: {'HeavyListItem': 160},
      );

      expect(issues.any((i) => i.title.contains('Crescimento Acentuado de Memória')), isTrue);
      expect(issues.any((i) => i.title.contains('Possível Vazamento na Rota Ativa: </relatorio>')), isTrue);
      expect(issues.any((i) => i.title.contains('Hotspot de Reconstrução: <HeavyListItem>')), isTrue);
    });
  });

  group('PerformanceDevBridge HTTP Endpoints Tests', () {
    late PerformanceMonitorService monitorService;
    late PerformanceDevBridge devBridge;
    const testPort = 8799;

    setUp(() async {
      HttpOverrides.global = null;
      monitorService = PerformanceMonitorService(
        enableDevBridge: false,
      );
      devBridge = PerformanceDevBridge(
        port: testPort,
        monitorService: monitorService,
      );
      await devBridge.start();
    });

    tearDown(() async {
      await devBridge.stop();
      monitorService.dispose();
    });

    test('GET /health returns ok status', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/health'));
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);

        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['status'], 'ok');
        expect(json['port'], testPort);
      } finally {
        client.close();
      }
    });

    test('GET /metrics returns performance data JSON', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/metrics'));
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);

        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json.containsKey('currentFps'), isTrue);
        expect(json.containsKey('averageFps'), isTrue);
        expect(json.containsKey('memoryRssMb'), isTrue);
      } finally {
        client.close();
      }
    });

    test('GET /rebuilds and POST /reset', () async {
      final client = HttpClient();
      try {
        PerformanceRebuildTracker().recordRebuild('SampleWidget');
        expect(PerformanceRebuildTracker().totalRebuilds, greaterThanOrEqualTo(1));

        // GET /rebuilds
        final reqGet = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/rebuilds'));
        final resGet = await reqGet.close();
        final bodyGet = await resGet.transform(utf8.decoder).join();
        final jsonGet = jsonDecode(bodyGet) as Map<String, dynamic>;
        expect(jsonGet['totalRebuilds'], greaterThanOrEqualTo(1));

        // POST /reset
        final reqPost = await client.postUrl(Uri.parse('http://127.0.0.1:$testPort/reset'));
        final resPost = await reqPost.close();
        expect(resPost.statusCode, HttpStatus.ok);
        expect(PerformanceRebuildTracker().totalRebuilds, 0);
      } finally {
        client.close();
      }
    });

    test('GET /diagnose returns analysis response', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/diagnose'));
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);

        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json.containsKey('status'), isTrue);
        expect(json.containsKey('issues'), isTrue);
      } finally {
        client.close();
      }
    });
  });
}
