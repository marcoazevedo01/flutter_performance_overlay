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
  int _activePort = 8765;
  bool _wantRunning = false;
  Map<String, dynamic>? _lastStreamChunk;
  final DateTime _startedAt = DateTime.now();

  bool get isRunning => _server != null;
  int get activePort => _activePort;

  PerformanceDevBridge({
    this.port = 8765,
    required this.monitorService,
  }) : _activePort = port;

  /// Inicia o servidor HTTP local na primeira porta livre no intervalo [port..port+9].
  Future<void> start() async {
    if (kIsWeb || _server != null || _wantRunning) return;
    _wantRunning = true;

    for (int candidatePort = port; candidatePort <= port + 9; candidatePort++) {
      try {
        await _activeServersByPort.remove(candidatePort)?.close(force: true);
        if (!_wantRunning) return;

        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidatePort,
          shared: false,
        );
        if (!_wantRunning) {
          await server.close(force: true);
          return;
        }

        _activePort = candidatePort;
        _server = server;
        _activeServersByPort[candidatePort] = server;
        server.listen(_handleRequest);
        debugPrint('[PerformanceDevBridge] Servidor de telemetria ativo em http://127.0.0.1:$candidatePort');
        return;
      } catch (e) {
        if (candidatePort == port + 9) {
          _wantRunning = false;
          debugPrint('[PerformanceDevBridge] Não foi possível iniciar entre portas $port..${port + 9}: $e');
        }
      }
    }
  }

  /// Para o servidor HTTP.
  Future<void> stop() async {
    _wantRunning = false;
    final server = _server;
    _server = null;
    if (server != null && identical(_activeServersByPort[_activePort], server)) {
      _activeServersByPort.remove(_activePort);
    }
    await server?.close(force: true);
  }

  static bool _isAllowedLocalOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  void _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;

    final origin = request.headers.value('origin');
    if (origin != null) {
      if (!_isAllowedLocalOrigin(origin)) {
        _sendJson(request, HttpStatus.forbidden, {'error': 'Origin not allowed'});
        return;
      }
      request.response.headers.add('Access-Control-Allow-Origin', origin);
      request.response.headers.add('Vary', 'Origin');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    }

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

        case '/stream/start':
          if (request.method == 'POST') {
            _lastStreamChunk = null;
            monitorService.startStreaming(
              interval: const Duration(seconds: 2),
              onChunk: _mergeStreamChunk,
            );
            _sendJson(request, HttpStatus.ok, {'status': 'started'});
          } else {
            _sendJson(request, HttpStatus.methodNotAllowed, {'error': 'Utilize método POST'});
          }
          break;

        case '/stream/stop':
          if (request.method == 'POST') {
            _mergeStreamChunk(monitorService.stopStreaming());
            final finalChunk = _lastStreamChunk;
            _lastStreamChunk = null;
            _sendJson(request, HttpStatus.ok, {'status': 'stopped', 'chunk': finalChunk});
          } else {
            _sendJson(request, HttpStatus.methodNotAllowed, {'error': 'Utilize método POST'});
          }
          break;

        case '/stream/chunk':
          final chunk = _lastStreamChunk ?? monitorService.buildCurrentChunk();
          _lastStreamChunk = null;
          _sendJson(request, HttpStatus.ok, chunk);
          break;

        case '/health':
        case '/':
          final uptime = DateTime.now().difference(_startedAt).inSeconds;
          _sendJson(request, HttpStatus.ok, {
            'status': 'ok',
            'port': _activePort,
            'uptimeSeconds': uptime,
            'instanceId': monitorService.instanceId,
            'appName': monitorService.effectiveAppName,
            'userName': monitorService.effectiveUserName,
            'device': monitorService.effectiveDeviceName,
            'version': monitorService.effectiveAppVersion,
            'appRoute': monitorService.lastData.currentRoute,
            'isStreaming': monitorService.isStreaming,
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

  void _mergeStreamChunk(Map<String, dynamic> chunk) {
    final prev = _lastStreamChunk;
    if (prev == null) {
      _lastStreamChunk = chunk;
      return;
    }
    _appendCapped(prev, chunk, 'samples', 200);
    _appendCapped(prev, chunk, 'logs', 200);
    _appendCapped(prev, chunk, 'errors', 50);
    _lastStreamChunk = chunk;
  }

  static void _appendCapped(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
    String key,
    int maxItems,
  ) {
    final combined = <dynamic>[
      ...(prev[key] as List? ?? const []),
      ...(next[key] as List? ?? const []),
    ];
    if (combined.length > maxItems) {
      combined.removeRange(0, combined.length - maxItems);
    }
    next[key] = combined;
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
