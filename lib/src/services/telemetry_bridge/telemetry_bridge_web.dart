import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

/// ponytail: Ponte de telemetria direta para Flutter Web via dart:js_interop.
/// Exporta métricas no objeto global 'window' para permitir que agentes de IA e ferramentas
/// de automação (Puppeteer, DevTools) extraiam telemetria estruturada sem depender de sockets TCP locais.
abstract final class WebTelemetryBridge {
  static Map<String, dynamic>? _lastSnapshot;

  static Map<String, dynamic>? get latestSnapshot => _lastSnapshot;

  static String? get latestSnapshotJson =>
      _lastSnapshot != null ? jsonEncode(_lastSnapshot) : null;

  static bool _semanticsHelperRegistered = false;

  static void export(Map<String, dynamic> data) {
    _lastSnapshot = data;
    _ensureSemanticsHelper();
    try {
      final jsonStr = jsonEncode(data);
      _window['__flutterPerformanceMetrics'] = jsonStr.toJS;
    } catch (_) {
      // Falha silenciosa caso o runtime JS bloqueie manipulação de window
    }
  }

  static void _ensureSemanticsHelper() {
    if (_semanticsHelperRegistered) return;
    _semanticsHelperRegistered = true;
    try {
      _window['__enableFlutterSemantics'] = (() {
        try {
          final doc = _window['document'] as JSObject?;
          if (doc != null) {
            final ph = doc.callMethod(
              'querySelector'.toJS,
              'flt-semantics-placeholder'.toJS,
            ) as JSObject?;
            if (ph != null) {
              ph.callMethod('click'.toJS);
              return true.toJS;
            }
          }
        } catch (_) {}
        return false.toJS;
      }).toJS;
    } catch (_) {}
  }
}
