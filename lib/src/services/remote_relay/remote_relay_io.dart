import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

/// Cliente WebSocket nativo (IO) para relay remoto (modo passivo ou painel inspector).
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService? monitorService;
  final bool isInspector;
  final void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated;
  final void Function(Map<String, dynamic> chunkEvent)? onChunkReceived;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false;
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

  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  void connect() {
    if (_disposed || _connecting || _socket != null) return;
    unawaited(_tryConnect());
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
      if (!isInspector && monitorService != null) {
        _send(RemoteRelayProtocol.buildRegisterPayload(monitorService!));
      } else if (isInspector && _hasPendingList) {
        _hasPendingList = false;
        _send({'type': 'list', 'authToken': _pendingListAuthToken});
      }

      _subscription = ws.listen(
        (raw) => RemoteRelayProtocol.handleMessage(
          raw: raw,
          monitor: monitorService,
          isInspector: isInspector,
          sendJson: _send,
          onInstancesUpdated: onInstancesUpdated,
          onChunkReceived: onChunkReceived,
        ),
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
