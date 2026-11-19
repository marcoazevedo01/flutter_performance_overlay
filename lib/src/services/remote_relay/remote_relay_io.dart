import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

/// Cliente WebSocket nativo (IO) para relay remoto (modo passivo ou painel inspector).
class PerformanceRemoteRelay with WidgetsBindingObserver {
  final String relayUrl;
  final String? relayKey;
  final String? authToken;
  final PerformanceMonitorService? monitorService;
  final bool isInspector;
  final Duration reconnectDelay;
  final void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated;
  final void Function(Map<String, dynamic> chunkEvent)? onChunkReceived;
  final void Function(RelayConnectionStatus status)? onStatusChanged;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  final List<Map<String, dynamic>> _pendingChunks = [];
  bool _disposed = false;
  bool _connecting = false;
  bool _hasConnectedBefore = false;
  bool _observerAttached = false;
  bool _hasPendingList = false;
  String? _pendingListAuthToken;
  RelayConnectionStatus _status = RelayConnectionStatus.disconnected;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    this.authToken,
    this.monitorService,
    this.isInspector = false,
    this.reconnectDelay = const Duration(seconds: 5),
    this.onInstancesUpdated,
    this.onChunkReceived,
    this.onStatusChanged,
  });

  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;
  RelayConnectionStatus get status => _status;

  void _setStatus(RelayConnectionStatus next) {
    if (_status == next) return;
    _status = next;
    onStatusChanged?.call(next);
  }

  void connect() {
    if (_disposed) return;
    if (!_observerAttached) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      } catch (_) {}
    }
    if (_connecting || _socket != null) return;
    unawaited(_tryConnect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed && !isConnected) {
      _reconnectTimer?.cancel();
      unawaited(_tryConnect());
    }
  }

  void refreshRegistration() {
    if (!isInspector && isConnected && monitorService != null) {
      _send(RemoteRelayProtocol.buildRegisterPayload(monitorService!));
    }
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
    _setStatus(
      _hasConnectedBefore
          ? RelayConnectionStatus.reconnecting
          : RelayConnectionStatus.connecting,
    );
    try {
      final uri = RemoteRelayProtocol.buildUri(relayUrl);
      final headers = (!isInspector && relayKey != null && relayKey!.isNotEmpty)
          ? {'x-perf-key': relayKey!}
          : null;
      final ws = await WebSocket.connect(uri.toString(), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (_disposed) {
        await ws.close();
        return;
      }

      ws.pingInterval = const Duration(seconds: 15);
      _socket = ws;
      _hasConnectedBefore = true;
      _setStatus(RelayConnectionStatus.connected);

      if (isInspector) {
        final authPayload = RemoteRelayProtocol.buildAuthPayload(
          authToken: authToken ?? _pendingListAuthToken,
        );
        if (authPayload != null) {
          _send(authPayload);
        }
      }

      if (!isInspector && monitorService != null) {
        _send(RemoteRelayProtocol.buildRegisterPayload(monitorService!));
        _flushPendingChunks();
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
    if (ws == null || ws.readyState != WebSocket.open) {
      if (payload['type'] == 'chunk') {
        RemoteRelayProtocol.enqueueChunk(_pendingChunks, payload);
      }
      return;
    }
    try {
      ws.add(jsonEncode(payload));
    } catch (_) {
      if (payload['type'] == 'chunk') {
        RemoteRelayProtocol.enqueueChunk(_pendingChunks, payload);
      }
    }
  }

  void _flushPendingChunks() {
    if (_pendingChunks.isEmpty) return;
    final items = List<Map<String, dynamic>>.from(_pendingChunks);
    _pendingChunks.clear();
    for (final item in items) {
      _send(item);
    }
  }

  void _onDisconnected() {
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setStatus(
      _hasConnectedBefore
          ? RelayConnectionStatus.reconnecting
          : RelayConnectionStatus.disconnected,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, _tryConnect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _pendingChunks.clear();
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _setStatus(RelayConnectionStatus.disconnected);
  }
}
