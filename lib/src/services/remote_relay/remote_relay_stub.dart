import '../performance_monitor_service.dart';

/// Implementação stub do cliente passivo de relay remoto.
class PerformanceRemoteRelay {
  final String relayUrl;
  final String? relayKey;
  final PerformanceMonitorService monitorService;

  PerformanceRemoteRelay({
    required this.relayUrl,
    this.relayKey,
    required this.monitorService,
  });

  void connect() {}

  void dispose() {}
}
