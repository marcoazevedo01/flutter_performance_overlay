import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({
    PerformanceOverlayConfig config = const PerformanceOverlayConfig(),
    PerformanceMonitorService? service,
    Widget? child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PerformanceOverlayWidget(
          config: config,
          monitorService: service,
          child: child ?? const Center(child: Text('App Content')),
        ),
      ),
    );
  }

  group('PerformanceOverlayWidget Anti-Regression Tests', () {
    testWidgets('Disabled overlay only renders child without overlay elements', (tester) async {
      await tester.pumpWidget(
        buildTestApp(config: const PerformanceOverlayConfig(enabled: false)),
      );

      expect(find.text('App Content'), findsOneWidget);
      expect(find.byType(MetricBadge), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('Compact mode renders FPS and RAM badges', (tester) async {
      await tester.pumpWidget(
        buildTestApp(config: const PerformanceOverlayConfig(startExpanded: false)),
      );

      expect(find.text('App Content'), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'FPS'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'RAM'), findsOneWidget);
    });

    testWidgets('Tapping overlay toggles between compact and expanded modes', (tester) async {
      await tester.pumpWidget(
        buildTestApp(config: const PerformanceOverlayConfig(startExpanded: false)),
      );

      // Inicia compacto (sem UI/GPU/Rota)
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'UI'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'Rota'), findsNothing);

      // Tap para expandir
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      // Agora deve conter as métricas expandidas
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'UI'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'GPU'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'Rota'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'Rebuilds'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'Event Loop Freeze'), findsOneWidget);

      // Tap novamente para compactar
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is MetricBadge && w.label == 'UI'), findsNothing);
    });

    testWidgets('Dragging overlay clamps position within screen bounds', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          config: const PerformanceOverlayConfig(
            initialPosition: Offset(100, 100),
          ),
        ),
      );

      final detector = find.byType(GestureDetector);

      // Tentar arrastar muito além do limite direito/inferior da tela (+2000px)
      await tester.drag(detector, const Offset(2000, 2000));
      await tester.pumpAndSettle();

      // Pega a posição resultante do Positioned widget
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.left! <= 800, isTrue);
      expect(positioned.top! <= 600, isTrue);
      expect(positioned.left! >= 0, isTrue);
      expect(positioned.top! >= 0, isTrue);

      // Tentar arrastar muito além do limite superior/esquerdo (-2000px)
      await tester.drag(detector, const Offset(-3000, -3000));
      await tester.pumpAndSettle();

      final positionedAfterLeft = tester.widget<Positioned>(find.byType(Positioned));
      expect(positionedAfterLeft.left, greaterThanOrEqualTo(0));
      expect(positionedAfterLeft.top, greaterThanOrEqualTo(0));
    });

    testWidgets('TrackRebuild widget increments rebuild count on rebuilds', (tester) async {
      final tracker = PerformanceRebuildTracker();
      tracker.reset();

      final rebuildNotifier = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: rebuildNotifier,
            builder: (context, val, _) {
              return TrackRebuild(
                id: 'TestWidget',
                child: Text('Value: $val'),
              );
            },
          ),
        ),
      );

      expect(tracker.totalRebuilds, 1);
      expect(tracker.rebuildsByWidget['TestWidget'], 1);

      rebuildNotifier.value = 1;
      await tester.pump();

      expect(tracker.totalRebuilds, 2);
      expect(tracker.rebuildsByWidget['TestWidget'], 2);
    });
  });
}
