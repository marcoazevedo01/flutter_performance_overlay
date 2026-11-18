import 'dart:convert';

import '../performance_monitor_service.dart';

/// Utilitários compartilhados de protocolo para o cliente passivo e o modo inspector do relay remoto.
abstract final class RemoteRelayProtocol {
  static Uri buildUri(String relayUrl, String? relayKey) {
    final uri = Uri.parse(relayUrl);
    if (relayKey == null || relayKey.isEmpty) return uri;
    final params = Map<String, String>.from(uri.queryParameters);
    params['key'] = relayKey;
    return uri.replace(queryParameters: params);
  }

  static Map<String, dynamic> buildRegisterPayload(PerformanceMonitorService monitor) => {
        'type': 'register',
        'instanceId': monitor.instanceId,
        'appName': monitor.effectiveAppName,
        'userName': monitor.userName,
        'device': monitor.effectiveDeviceName,
        'version': monitor.appVersion ?? '1.0.0',
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
        'version': monitor.appVersion ?? '1.0.0',
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
