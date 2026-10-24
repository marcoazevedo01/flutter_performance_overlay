import 'dart:convert';

/// ponytail: Implementação stub em memória para plataformas não-web.
/// Em plataformas nativas (IO), o canal primário com agentes MCP é via PerformanceDevBridge (HttpServer na porta 8765).
abstract final class WebTelemetryBridge {
  static Map<String, dynamic>? _lastSnapshot;

  static Map<String, dynamic>? get latestSnapshot => _lastSnapshot;

  static String? get latestSnapshotJson =>
      _lastSnapshot != null ? jsonEncode(_lastSnapshot) : null;

  static void export(Map<String, dynamic> data) {
    _lastSnapshot = data;
  }
}
