import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

@JS('WebSocket')
external JSFunction get _webSocketConstructor;

/// Cliente WebSocket nativo (Browser JS Interop) para relay remoto (modo passivo ou inspector).
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

  JSObject? _socket;
  Timer? _reconnectTimer;
  final List<Map<String, dynamic>> _pendingChunks = [];
  bool _disposed = false;
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

  bool get isConnected {
    final state = _socket?['readyState']?.dartify();
    return state is num && state.toInt() == 1;
  }

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
    if (_socket != null) return;
    _tryConnect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed && !isConnected) {
      _reconnectTimer?.cancel();
      _tryConnect();
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

  void _tryConnect() {
    if (_disposed) return;
    _setStatus(
      _hasConnectedBefore
          ? RelayConnectionStatus.reconnecting
          : RelayConnectionStatus.connecting,
    );
    try {
      final uri = RemoteRelayProtocol.buildUri(relayUrl);
      final ws = _webSocketConstructor.callAsConstructor<JSObject>(uri.toString().toJS);
      _socket = ws;

      ws['onopen'] = ((JSAny? _) {
        if (_disposed) return;
        _hasConnectedBefore = true;
        _setStatus(RelayConnectionStatus.connected);
        final authPayload = RemoteRelayProtocol.buildAuthPayload(
          relayKey: isInspector ? null : relayKey,
          authToken: isInspector ? (authToken ?? _pendingListAuthToken) : null,
        );
        if (authPayload != null) {
          _send(authPayload);
        }
        if (!isInspector && monitorService != null) {
          _send(RemoteRelayProtocol.buildRegisterPayload(monitorService!));
          _flushPendingChunks();
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
    if (ws == null) {
      if (payload['type'] == 'chunk') {
        RemoteRelayProtocol.enqueueChunk(_pendingChunks, payload);
      }
      return;
    }
    final state = ws['readyState']?.dartify();
    if (state is! num || state.toInt() != 1) {
      if (payload['type'] == 'chunk') {
        RemoteRelayProtocol.enqueueChunk(_pendingChunks, payload);
      }
      return;
    }
    try {
      ws.callMethod('send'.toJS, jsonEncode(payload).toJS);
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
    _pendingChunks.clear();
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    try {
      _socket?.callMethod('close'.toJS);
    } catch (_) {}
    _socket = null;
    _setStatus(RelayConnectionStatus.disconnected);
  }
}
