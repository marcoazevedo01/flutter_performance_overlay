import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_performance_overlay/src/services/telemetry_bridge/telemetry_bridge.dart';

void main() {
  group('WebTelemetryBridge Tests', () {
    test('Stub exports telemetry data and stores latest snapshot in memory', () {
      final sample = {
        'fps': 60.0,
        'memoryRssMb': 128.5,
        'currentRoute': '/home',
      };

      WebTelemetryBridge.export(sample);
      expect(WebTelemetryBridge.latestSnapshot, equals(sample));
      expect(WebTelemetryBridge.latestSnapshotJson, contains('"fps":60.0'));
    });
  });
}
