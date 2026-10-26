import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import 'performance_diagnostics.dart';
import 'performance_monitor_service.dart';
import 'rebuild_tracker.dart';

/// Registra extensões de serviço nativas no Dart VM Service para integração
/// direta com Dart Tooling Daemon (DTD), Flutter DevTools e Agentes de IA (MCP).
class PerformanceServiceExtensions {
  static const String prefix = 'ext.flutter_performance';

  static PerformanceServiceExtensions? _activeInstance;
  static bool _registeredGlobally = false;

  final PerformanceMonitorService monitorService;
  final PerformanceRebuildTracker rebuildTracker;

  PerformanceServiceExtensions({
    required this.monitorService,
    PerformanceRebuildTracker? rebuildTracker,
  }) : rebuildTracker = rebuildTracker ?? PerformanceRebuildTracker();

  /// ponytail: A VM Dart não permite desregistrar extensões no Isolate.
  /// Usamos um despachante estático único que delega para a instância ativa.
  void register() {
    _activeInstance = this;
    if (kIsWeb || _registeredGlobally) return;

    final methods = <String>[
      '$prefix.getMetrics',
      '$prefix.getHistory',
      '$prefix.getRebuilds',
      '$prefix.diagnose',
      '$prefix.reset',
    ];

    for (final method in methods) {
      try {
        developer.registerExtension(
          method,
          (m, params) async {
            if (_activeInstance != null) {
              return _activeInstance!.handleMethod(m, params);
            }
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionErrorMin,
              jsonEncode({'error': 'Nenhuma instância ativa de telemetria encontrada.'}),
            );
          },
        );
      } catch (_) {
        // Já registrado na VM por outro teste/execução anterior
      }
    }

    _registeredGlobally = true;
  }

  /// Desativa esta instância como recebedora ativa das chamadas da VM.
  void unregister() {
    if (_activeInstance == this) {
      _activeInstance = null;
    }
  }

  /// Processa chamadas RPC recebidas via VM Service ou chamadas diretas de teste.
  Future<developer.ServiceExtensionResponse> handleMethod(
    String method,
    Map<String, String> parameters,
  ) async {
    try {
      switch (method) {
        case '$prefix.getMetrics':
          final data = monitorService.lastData.toJson();
          return developer.ServiceExtensionResponse.result(jsonEncode(data));

        case '$prefix.getHistory':
          final history = monitorService.history.map((e) => e.toJson()).toList();
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'count': history.length, 'history': history}),
          );

        case '$prefix.getRebuilds':
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'totalRebuilds': rebuildTracker.totalRebuilds,
              'rebuildsByWidget': rebuildTracker.rebuildsByWidget,
            }),
          );

        case '$prefix.diagnose':
          final issues = PerformanceDiagnostics.analyze(
            currentData: monitorService.lastData,
            history: monitorService.history,
            rebuildsByWidget: rebuildTracker.rebuildsByWidget,
          );
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'status': issues.isEmpty ? 'healthy' : 'issues_found',
              'issuesCount': issues.length,
              'currentMetrics': monitorService.lastData.toJson(),
              'issues': issues.map((e) => e.toJson()).toList(),
            }),
          );

        case '$prefix.reset':
          rebuildTracker.reset();
          monitorService.clearHistory();
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'success': true,
              'message': 'Métricas e contadores de rebuilds resetados via VM Service.',
            }),
          );

        default:
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionErrorMin,
            jsonEncode({'error': 'Método não reconhecido: $method'}),
          );
      }
    } catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionErrorMin,
        jsonEncode({'error': e.toString()}),
      );
    }
  }
}
