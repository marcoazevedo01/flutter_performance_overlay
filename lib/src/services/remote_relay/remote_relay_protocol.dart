import 'dart:convert';

import '../performance_monitor_service.dart';

/// Utilitários compartilhados de protocolo para o cliente passivo de telemetria remota.
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

  static void handleMessage(
    dynamic raw,
    PerformanceMonitorService monitor,
    void Function(Map<String, dynamic> payload) sendJson,
  ) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final type = data['type'];
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
