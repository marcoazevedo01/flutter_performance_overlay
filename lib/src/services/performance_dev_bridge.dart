import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'performance_diagnostics.dart';
import 'performance_monitor_service.dart';
import 'rebuild_tracker.dart';

/// Mini servidor HTTP local para expor telemetria de performance em tempo real
/// para agentes de IA (via MCP), DevTools e ferramentas de inspeção.
class PerformanceDevBridge {
  static final Map<int, HttpServer> _activeServersByPort = {};

  final int port;
  final PerformanceMonitorService monitorService;

  HttpServer? _server;
  bool _wantRunning = false;
  final DateTime _startedAt = DateTime.now();

  bool get isRunning => _server != null;

  PerformanceDevBridge({
    this.port = 8765,
    required this.monitorService,
  });

  /// Inicia o servidor HTTP local na porta configurada.
  Future<void> start() async {
    if (kIsWeb || _server != null || _wantRunning) return;
    _wantRunning = true;

    try {
      await _activeServersByPort.remove(port)?.close(force: true);
      if (!_wantRunning) return;

      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      if (!_wantRunning) {
        await server.close(force: true);
        return;
      }

      _server = server;
      _activeServersByPort[port] = server;
      server.listen(_handleRequest);
      debugPrint('[PerformanceDevBridge] Servidor de telemetria ativo em http://127.0.0.1:$port');
    } catch (e) {
      _wantRunning = false;
      debugPrint('[PerformanceDevBridge] Não foi possível iniciar na porta $port: $e');
    }
  }

  /// Para o servidor HTTP.
  Future<void> stop() async {
    _wantRunning = false;
    final server = _server;
    _server = null;
    if (server != null && identical(_activeServersByPort[port], server)) {
      _activeServersByPort.remove(port);
    }
    await server?.close(force: true);
  }

  void _handleRequest(HttpRequest request) async {
    // Permite chamadas locais e de extensões
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    request.response.headers.contentType = ContentType.json;

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      switch (path) {
        case '/metrics':
        case '/snapshot':
          final data = monitorService.lastData.toJson();
          _sendJson(request, HttpStatus.ok, data);
          break;

        case '/history':
          final history = monitorService.history.map((e) => e.toJson()).toList();
          _sendJson(request, HttpStatus.ok, {
            'count': history.length,
            'history': history,
          });
          break;

        case '/rebuilds':
          final tracker = PerformanceRebuildTracker();
          _sendJson(request, HttpStatus.ok, {
            'totalRebuilds': tracker.totalRebuilds,
            'rebuildsByWidget': tracker.rebuildsByWidget,
          });
          break;

        case '/diagnose':
          final tracker = PerformanceRebuildTracker();
          final issues = PerformanceDiagnostics.analyze(
            currentData: monitorService.lastData,
            history: monitorService.history,
            rebuildsByWidget: tracker.rebuildsByWidget,
          );
          _sendJson(request, HttpStatus.ok, {
            'status': issues.isEmpty ? 'healthy' : 'issues_found',
            'issuesCount': issues.length,
            'currentMetrics': monitorService.lastData.toJson(),
            'issues': issues.map((e) => e.toJson()).toList(),
          });
          break;

        case '/reset':
          if (request.method == 'POST') {
            PerformanceRebuildTracker().reset();
            monitorService.clearHistory();
            _sendJson(request, HttpStatus.ok, {
              'success': true,
              'message': 'Métricas e contadores de rebuilds foram resetados.',
            });
          } else {
            _sendJson(request, HttpStatus.methodNotAllowed, {'error': 'Utilize método POST'});
          }
          break;

        case '/health':
        case '/':
          final uptime = DateTime.now().difference(_startedAt).inSeconds;
          _sendJson(request, HttpStatus.ok, {
            'status': 'ok',
            'port': port,
            'uptimeSeconds': uptime,
            'appRoute': monitorService.lastData.currentRoute,
          });
          break;

        default:
          _sendJson(request, HttpStatus.notFound, {
            'error': 'Endpoint não encontrado',
            'availableEndpoints': [
              '/metrics',
              '/history',
              '/rebuilds',
              '/diagnose',
              '/reset',
              '/health',
            ],
          });
      }
    } catch (e) {
      _sendJson(request, HttpStatus.internalServerError, {'error': e.toString()});
    }
  }

  void _sendJson(HttpRequest request, int statusCode, dynamic data) {
    request.response.statusCode = statusCode;
    request.response.write(jsonEncode(data));
    request.response.close();
  }

  void dispose() {
    stop();
  }
}
