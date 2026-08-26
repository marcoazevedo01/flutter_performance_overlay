import 'package:flutter/widgets.dart';

/// Gerenciador para rastrear e contabilizar reconstruções de widgets no app.
class PerformanceRebuildTracker {
  static final PerformanceRebuildTracker _instance = PerformanceRebuildTracker._internal();
  factory PerformanceRebuildTracker() => _instance;
  PerformanceRebuildTracker._internal();

  int _totalRebuilds = 0;
  final Map<String, int> _rebuildsByWidget = {};

  int get totalRebuilds => _totalRebuilds;
  Map<String, int> get rebuildsByWidget => Map.unmodifiable(_rebuildsByWidget);

  /// Incrementa a contagem de reconstruções para um widget identificado por [widgetId].
  void recordRebuild(String widgetId) {
    _totalRebuilds++;
    _rebuildsByWidget[widgetId] = (_rebuildsByWidget[widgetId] ?? 0) + 1;
  }

  /// Limpa todas as métricas acumuladas de rebuilds.
  void reset() {
    _totalRebuilds = 0;
    _rebuildsByWidget.clear();
  }
}

/// Widget utilitário que registra automaticamente um rebuild no [PerformanceRebuildTracker]
/// toda vez que seu método build é executado.
class TrackRebuild extends StatelessWidget {
  final String id;
  final Widget child;

  const TrackRebuild({
    super.key,
    required this.id,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    PerformanceRebuildTracker().recordRebuild(id);
    return child;
  }
}
