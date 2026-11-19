import '../performance_monitor_service.dart';
import 'remote_relay_protocol.dart';

/// Implementação stub do cliente de relay remoto (modo passivo ou inspector).
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final String? authToken;
  final PerformanceMonitorService? monitorService;
  final bool isInspector;
  final Duration reconnectDelay;
  final void Function(List<Map<String, dynamic>> instances)? onInstancesUpdated;
  final void Function(Map<String, dynamic> chunkEvent)? onChunkReceived;
  final void Function(RelayConnectionStatus status)? onStatusChanged;

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

  bool get isConnected => false;
  RelayConnectionStatus get status => RelayConnectionStatus.disconnected;

  void connect() {}

  void refreshRegistration() {}

  void requestInstances({String? authToken}) {}

  void startInstance(
    String targetInstanceId, {
    String? authToken,
    int intervalSec = 3,
  }) {}

  void stopInstance(String targetInstanceId, {String? authToken}) {}

  void dispose() {}
}
