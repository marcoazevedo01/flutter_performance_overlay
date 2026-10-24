import 'dart:async';
import 'package:http/http.dart' as http;

/// Rastreador leve de latência de chamadas HTTP/rede.
/// ponytail: Armazena em memória as últimas 50 latências para cálculo de média móvel sem impacto de performance.
class PerformanceNetworkTracker {
  static final PerformanceNetworkTracker _instance =
      PerformanceNetworkTracker._internal();

  factory PerformanceNetworkTracker() => _instance;

  PerformanceNetworkTracker._internal();

  final List<double> _recentLatencies = [];
  double _lastLatencyMs = 0.0;

  /// Retorna a duração da última requisição em milissegundos.
  double get lastLatencyMs => _lastLatencyMs;

  /// Retorna a média das últimas requisições em milissegundos.
  double get averageLatencyMs {
    if (_recentLatencies.isEmpty) return 0.0;
    final sum = _recentLatencies.fold(0.0, (a, b) => a + b);
    return sum / _recentLatencies.length;
  }

  /// Registra a duração de uma requisição em milissegundos.
  void recordLatency(double durationMs) {
    _lastLatencyMs = durationMs;
    _recentLatencies.add(durationMs);
    if (_recentLatencies.length > 50) {
      _recentLatencies.removeAt(0);
    }
  }

  /// Utilitário para medir automaticamente a duração de qualquer operação assíncrona.
  static Future<T> track<T>(Future<T> Function() call) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await call();
    } finally {
      stopwatch.stop();
      _instance.recordLatency(stopwatch.elapsedMilliseconds.toDouble());
    }
  }

  /// Zera o histórico de latências.
  void reset() {
    _recentLatencies.clear();
    _lastLatencyMs = 0.0;
  }
}

/// Cliente HTTP transparente que intercepta e registra a duração de requisições no [PerformanceNetworkTracker].
class PerformanceHttpClient extends http.BaseClient {
  final http.Client _inner;

  PerformanceHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await _inner.send(request);
    } finally {
      stopwatch.stop();
      PerformanceNetworkTracker().recordLatency(stopwatch.elapsedMilliseconds.toDouble());
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
