import '../performance_monitor_service.dart';

/// Implementação stub do cliente de relay remoto (modo passivo ou inspector).
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService? monitorService;
  final bool isInspector;
  final void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated;
  final void Function(Map<String, dynamic> chunkEvent)? onChunkReceived;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    this.monitorService,
    this.isInspector = false,
    this.onInstancesUpdated,
    this.onChunkReceived,
  });

  bool get isConnected => false;

  void connect() {}

  void requestInstances({String? authToken}) {}

  void startInstance(
    String targetInstanceId, {
    String? authToken,
    int intervalSec = 3,
  }) {}

  void stopInstance(String targetInstanceId, {String? authToken}) {}

  void dispose() {}
}
