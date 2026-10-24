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
      expect(data.peakMemoryRssMb, 0.0);
      expect(data.eventLoopLagMs, 0.0);
      expect(data.currentRoute, '/');
      expect(data.rebuildCount, 0);
      expect(data.routeMountDurationMs, 0.0);
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
      expect(json['peakMemoryRssMb'], 80.12);
      expect(json['eventLoopLagMs'], 12.3);
      expect(json['currentRoute'], '/detalhes');
      expect(json['rebuildCount'], 42);
      expect(json['routeMountDurationMs'], 0.0);
    });

    test('PerformanceData.copyWith() updates new metrics properly', () {
      final initial = PerformanceData.initial();
      final updated = initial.copyWith(
        currentFps: 45.0,
        memoryRssMb: 100.5,
        deltaMemoryRssMb: 2.5,
        currentRoute: '/login',
        rebuildCount: 10,
      );

      expect(updated.currentFps, 45.0);
      expect(updated.memoryRssMb, 100.5);
      expect(updated.deltaMemoryRssMb, 2.5);
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
}
