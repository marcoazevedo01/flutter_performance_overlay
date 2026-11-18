import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

@JS('WebSocket')
external JSFunction get _webSocketConstructor;

/// Cliente WebSocket nativo (Browser JS Interop) para relay remoto (modo passivo ou inspector).
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService? monitorService;
  final bool isInspector;
  final void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated;
  final void Function(Map<String, dynamic> chunkEvent)? onChunkReceived;

  JSObject? _socket;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _hasPendingList = false;
  String? _pendingListAuthToken;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    this.monitorService,
    this.isInspector = false,
    this.onInstancesUpdated,
    this.onChunkReceived,
  });

  bool get isConnected {
    final state = _socket?['readyState']?.dartify();
    return state is num && state.toInt() == 1;
  }

  void connect() {
    if (_disposed || _socket != null) return;
    _tryConnect();
  }

  void requestInstances({String? authToken}) {
    if (!isInspector) return;
    if (!isConnected) {
      _hasPendingList = true;
      _pendingListAuthToken = authToken;
      connect();
      return;
    }
    _send({'type': 'list', 'authToken': authToken});
  }

  void startInstance(
    String targetInstanceId, {
    String? authToken,
    int intervalSec = 3,
  }) {
    if (!isInspector) return;
    _send({
      'type': 'start_target',
      'targetInstanceId': targetInstanceId,
      'intervalSec': intervalSec,
      'authToken': authToken,
    });
  }

  void stopInstance(String targetInstanceId, {String? authToken}) {
    if (!isInspector) return;
    _send({
      'type': 'stop_target',
      'targetInstanceId': targetInstanceId,
      'authToken': authToken,
    });
  }

  void _tryConnect() {
    if (_disposed) return;
    try {
      final uri = RemoteRelayProtocol.buildUri(relayUrl, relayKey);
      final ws = _webSocketConstructor.callAsConstructor<JSObject>(uri.toString().toJS);
      _socket = ws;

      ws['onopen'] = ((JSAny? _) {
        if (_disposed) return;
        if (!isInspector && monitorService != null) {
          _send(RemoteRelayProtocol.buildRegisterPayload(monitorService!));
        } else if (isInspector && _hasPendingList) {
          _hasPendingList = false;
          _send({'type': 'list', 'authToken': _pendingListAuthToken});
        }
      }).toJS;

      ws['onmessage'] = ((JSObject event) {
        if (_disposed) return;
        final data = event['data']?.dartify();
        if (data is String) {
          RemoteRelayProtocol.handleMessage(
            raw: data,
            monitor: monitorService,
            isInspector: isInspector,
            sendJson: _send,
            onInstancesUpdated: onInstancesUpdated,
            onChunkReceived: onChunkReceived,
          );
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
