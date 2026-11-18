import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

@JS('WebSocket')
external JSFunction get _webSocketConstructor;

/// Cliente WebSocket nativo (Browser JS Interop) passivo para receber comandos start/stop.
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService monitorService;

  JSObject? _socket;
  Timer? _reconnectTimer;
  bool _disposed = false;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    required this.monitorService,
  });

  void connect() {
    if (_disposed || _socket != null) return;
    _tryConnect();
  }

  void _tryConnect() {
    if (_disposed) return;
    try {
      final uri = RemoteRelayProtocol.buildUri(relayUrl, relayKey);
      final ws = _webSocketConstructor.callAsConstructor<JSObject>(uri.toString().toJS);
      _socket = ws;

      ws['onopen'] = ((JSAny? _) {
        if (_disposed) return;
        _send(RemoteRelayProtocol.buildRegisterPayload(monitorService));
      }).toJS;

      ws['onmessage'] = ((JSObject event) {
        if (_disposed) return;
        final data = event['data']?.dartify();
        if (data is String) {
          RemoteRelayProtocol.handleMessage(data, monitorService, _send);
        }
      }).toJS;

      ws['onclose'] = ((JSAny? _) => _onDisconnected()).toJS;
      ws['onerror'] = ((JSAny? _) => _onDisconnected()).toJS;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> payload) {
    final ws = _socket;
    if (ws == null) return;
    final state = ws['readyState']?.dartify();
    if (state is! num || state.toInt() != 1) {
      return;
    }
    try {
      ws.callMethod('send'.toJS, jsonEncode(payload).toJS);
    } catch (_) {}
  }

  void _onDisconnected() {
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 8), _tryConnect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _socket?.callMethod('close'.toJS);
    } catch (_) {}
    _socket = null;
  }
}
