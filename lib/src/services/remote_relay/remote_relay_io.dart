import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

/// Cliente WebSocket nativo (IO) passivo para receber comandos start/stop do servidor configurado.
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService monitorService;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    required this.monitorService,
  });

  void connect() {
    if (_disposed || _connecting || _socket != null) return;
    unawaited(_tryConnect());
  }

  Future<void> _tryConnect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    try {
      final uri = RemoteRelayProtocol.buildUri(relayUrl, relayKey);
      final headers = (relayKey != null && relayKey!.isNotEmpty)
          ? {'x-perf-key': relayKey!}
          : null;
      final ws = await WebSocket.connect(uri.toString(), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (_disposed) {
        await ws.close();
        return;
      }

      _socket = ws;
      _send(RemoteRelayProtocol.buildRegisterPayload(monitorService));

      _subscription = ws.listen(
        (raw) => RemoteRelayProtocol.handleMessage(raw, monitorService, _send),
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _send(Map<String, dynamic> payload) {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _onDisconnected() {
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // ponytail: backoff fixo simples de 8s para reconexão passiva
    _reconnectTimer = Timer(const Duration(seconds: 8), _tryConnect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
