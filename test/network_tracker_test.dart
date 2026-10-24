import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() {
  group('PerformanceNetworkTracker Tests', () {
    setUp(() {
      PerformanceNetworkTracker().reset();
    });

    test('Record latencies and compute average', () {
      final tracker = PerformanceNetworkTracker();
      expect(tracker.averageLatencyMs, 0.0);
      expect(tracker.lastLatencyMs, 0.0);

      tracker.recordLatency(100.0);
      tracker.recordLatency(200.0);

      expect(tracker.lastLatencyMs, 200.0);
      expect(tracker.averageLatencyMs, 150.0);
    });

    test('PerformanceNetworkTracker.track measures async execution duration', () async {
      final tracker = PerformanceNetworkTracker();
      final result = await PerformanceNetworkTracker.track(() async {
        await Future.delayed(const Duration(milliseconds: 20));
        return 42;
      });

      expect(result, 42);
      expect(tracker.lastLatencyMs >= 15.0, true);
      expect(tracker.averageLatencyMs >= 15.0, true);
    });

    test('PerformanceHttpClient intercepts requests and records latency', () async {
      final tracker = PerformanceNetworkTracker();
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 15));
        return http.Response('{"ok": true}', 200);
      });

      final client = PerformanceHttpClient(mockClient);
      final response = await client.get(Uri.parse('https://api.exemplo.com/dados'));

      expect(response.statusCode, 200);
      expect(tracker.lastLatencyMs >= 10.0, true);
      client.close();
    });
  });
}
