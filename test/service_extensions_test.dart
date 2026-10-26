import 'dart:convert';
import 'dart:developer';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceServiceExtensions RPC Tests', () {
    late PerformanceMonitorService monitorService;
    late PerformanceServiceExtensions serviceExtensions;

    setUp(() {
      monitorService = PerformanceMonitorService(enableDevBridge: false);
      serviceExtensions = PerformanceServiceExtensions(
        monitorService: monitorService,
      );
    });

    tearDown(() {
      monitorService.dispose();
    });

    test('ext.flutter_performance.getMetrics returns current metrics JSON', () async {
      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.getMetrics',
        {},
      );

      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json.containsKey('currentFps'), isTrue);
      expect(json.containsKey('averageFps'), isTrue);
      expect(json.containsKey('memoryRssMb'), isTrue);
    });

    test('ext.flutter_performance.getHistory returns history list JSON', () async {
      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.getHistory',
        {},
      );

      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json.containsKey('count'), isTrue);
      expect(json.containsKey('history'), isTrue);
    });

    test('ext.flutter_performance.getRebuilds returns rebuild counters', () async {
      PerformanceRebuildTracker().recordRebuild('TestWidget');

      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.getRebuilds',
        {},
      );

      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json.containsKey('totalRebuilds'), isTrue);
      expect(json['totalRebuilds'], greaterThanOrEqualTo(1));
      expect(json['rebuildsByWidget'], contains('TestWidget'));
    });

    test('ext.flutter_performance.diagnose returns diagnostics analysis', () async {
      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.diagnose',
        {},
      );

      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json.containsKey('status'), isTrue);
      expect(json.containsKey('issuesCount'), isTrue);
      expect(json.containsKey('issues'), isTrue);
    });

    test('ext.flutter_performance.reset resets metrics and rebuilds', () async {
      PerformanceRebuildTracker().recordRebuild('ResetWidget');
      expect(PerformanceRebuildTracker().totalRebuilds, greaterThanOrEqualTo(1));

      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.reset',
        {},
      );

      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(PerformanceRebuildTracker().totalRebuilds, 0);
    });

    test('unknown method returns error response', () async {
      final response = await serviceExtensions.handleMethod(
        'ext.flutter_performance.unknown',
        {},
      );

      expect(response.errorCode, equals(ServiceExtensionResponse.extensionErrorMin));
      final errorJson = jsonDecode(response.errorDetail!) as Map<String, dynamic>;
      expect(errorJson['error'], contains('Método não reconhecido'));
    });
  });
}
