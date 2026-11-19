import 'dart:convert';

import '../performance_monitor_service.dart';

/// Estado atual da conexão com o servidor de relay remoto.
enum RelayConnectionStatus { disconnected, connecting, connected, reconnecting }

/// Utilitários compartilhados de protocolo para o cliente passivo e o modo inspector do relay remoto.
abstract final class RemoteRelayProtocol {
  static void enqueueChunk(List<Map<String, dynamic>> buffer, Map<String, dynamic> payload) {
    // ponytail: buffer circular de 10 chunks para suportar oscilações 3G/4G sem inflar RAM
    if (buffer.length >= 10) {
      buffer.removeAt(0);
    }
    buffer.add(payload);
  }

  static Uri buildUri(String relayUrl) => Uri.parse(relayUrl);

  static Map<String, dynamic>? buildAuthPayload({
    String? relayKey,
    String? authToken,
  }) {
    if (authToken != null && authToken.isNotEmpty) {
      return {'type': 'auth', 'authToken': authToken};
    }
    if (relayKey != null && relayKey.isNotEmpty) {
      return {'type': 'auth', 'key': relayKey};
    }
    return null;
  }

  static Map<String, dynamic> buildRegisterPayload(PerformanceMonitorService monitor) => {
        'type': 'register',
        'instanceId': monitor.instanceId,
        'appName': monitor.effectiveAppName,
        'userName': monitor.effectiveUserName,
        'device': monitor.effectiveDeviceName,
        'version': monitor.effectiveAppVersion,
      };

  static Map<String, dynamic> buildChunkPayload(
    PerformanceMonitorService monitor,
    dynamic requesterId,
    Map<String, dynamic> chunk,
  ) =>
      {
        'type': 'chunk',
        'requesterId': requesterId,
        'instanceId': monitor.instanceId,
        'appName': monitor.effectiveAppName,
        'device': monitor.effectiveDeviceName,
        'version': monitor.effectiveAppVersion,
        'chunk': chunk,
      };

  static void handleMessage({
    required dynamic raw,
    PerformanceMonitorService? monitor,
    required bool isInspector,
    required void Function(Map<String, dynamic> payload) sendJson,
    void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated,
    void Function(Map<String, dynamic> chunkEvent)? onChunkReceived,
  }) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type'];

      if (isInspector) {
        if (type == 'instances' && data['list'] is List) {
          final list = (data['list'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          onInstancesUpdated?.call(list);
        } else if (type == 'chunk') {
          onChunkReceived?.call(data);
        }
        return;
      }

      if (monitor == null) return;
      if (type == 'start') {
        final requesterId = data['requesterId'];
        final intervalSec = ((data['intervalSec'] as num?)?.toInt() ?? 3).clamp(1, 30);
        monitor.startStreaming(
          interval: Duration(seconds: intervalSec),
          onChunk: (chunk) => sendJson(buildChunkPayload(monitor, requesterId, chunk)),
        );
      } else if (type == 'stop') {
        final finalChunk = monitor.stopStreaming();
        if (data['requesterId'] != null) {
          sendJson(buildChunkPayload(monitor, data['requesterId'], finalChunk));
        }
      }
    } catch (_) {}
  }
}
