import 'dart:async';

/// Detector leve de congelamento/latência no Event Loop do Dart.
///
/// Mede o atraso entre o agendamento de uma tarefa periódica e sua execução real.
/// Se um código síncrono pesado bloquear a thread principal, o atraso aumentará.
class EventLoopLagDetector {
  final Duration interval;
  final void Function(double lagInMs)? onLagDetected;

  Timer? _timer;
  int _lastTickTimestamp = 0;
  double _currentLagMs = 0.0;

  double get currentLagMs => _currentLagMs;

  EventLoopLagDetector({
    this.interval = const Duration(milliseconds: 200),
    this.onLagDetected,
  });

  void start() {
    stop();
    _lastTickTimestamp = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(interval, (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final expectedDelta = interval.inMilliseconds;
      final actualDelta = now - _lastTickTimestamp;
      _lastTickTimestamp = now;

      final lag = (actualDelta - expectedDelta).clamp(0, 5000).toDouble();
      _currentLagMs = lag;

      if (onLagDetected != null) {
        onLagDetected!(lag);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _currentLagMs = 0.0;
  }

  void dispose() {
    stop();
  }
}
