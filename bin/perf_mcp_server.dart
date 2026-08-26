import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// URL remota do script no GitHub para auto-atualização automática em background.
const String _remoteScriptUrl =
    'https://raw.githubusercontent.com/marcoazevedo01/flutter_performance_overlay/main/bin/perf_mcp_server.dart';

void main(List<String> args) async {
  final server = PerformanceMcpServer();
  // Dispara a checagem de auto-atualização em background sem bloquear o handshake do MCP
  unawaited(server.checkForSelfUpdate());
  await server.run();
}

class PerformanceMcpServer {
  final String devBridgeBaseUrl;
  final HttpClient _httpClient = HttpClient();

  PerformanceMcpServer({this.devBridgeBaseUrl = 'http://127.0.0.1:8765'});

  /// Verifica e atualiza o próprio arquivo local caso haja novidades no GitHub.
  Future<void> checkForSelfUpdate() async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(_remoteScriptUrl));
      final response = await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == HttpStatus.ok) {
        final remoteCode = await response.transform(utf8.decoder).join();
        final localFile = File(Platform.script.toFilePath());

        if (await localFile.exists()) {
          final localCode = await localFile.readAsString();
          if (remoteCode.trim().isNotEmpty && remoteCode != localCode) {
            await localFile.writeAsString(remoteCode, flush: true);
          }
        }
      }
    } catch (_) {
      // Ignora silenciosamente se estiver offline para não interferir no MCP
    }
  }

  Future<void> run() async {
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) async {
        if (line.trim().isEmpty) return;
        try {
          final request = jsonDecode(line) as Map<String, dynamic>;
          final response = await _handleMessage(request);
          if (response != null) {
            stdout.writeln(jsonEncode(response));
          }
        } catch (e) {
          final errorResponse = {
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32700, 'message': 'Parse error: $e'},
          };
          stdout.writeln(jsonEncode(errorResponse));
        }
      },
    );
  }

  Future<Map<String, dynamic>?> _handleMessage(Map<String, dynamic> req) async {
    final method = req['method'] as String?;
    final id = req['id'];

    switch (method) {
      case 'initialize':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': '2024-11-05',
            'capabilities': {
              'tools': {},
            },
            'serverInfo': {
              'name': 'flutter-performance-mcp-server',
              'version': '0.1.0',
            },
          },
        };

      case 'tools/list':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'tools': [
              {
                'name': 'get_live_metrics',
                'description':
                    'Obtém as métricas de desempenho ao vivo do app Flutter em execução (FPS, UI/GPU build time, RAM, Delta RAM, Rota e Rebuilds).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'audit_performance_issues',
                'description':
                    'Audita a performance recente do app Flutter e retorna anomalias diagnosticadas (queda de FPS, Jank excessivo, gargalos de UI/GPU, congelamento de Event Loop e suspeitas de vazamento de memória).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_rebuild_hotspots',
                'description':
                    'Lista o ranking dos widgets que mais sofreram reconstruções (rebuilds) na árvore de componentes para identificar componentes com rebuild excessivo.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'analyze_performance_log_file',
                'description':
                    'Analisa um arquivo de log JSON de telemetria exportado pelo app em disco e emite um relatório detalhado de saúde e anomalias.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'filePath': {
                      'type': 'string',
                      'description': 'Caminho absoluto do arquivo JSON de log de performance.',
                    },
                  },
                  'required': ['filePath'],
                },
              },
              {
                'name': 'reset_performance_metrics',
                'description':
                    'Zera os contadores de rebuilds e histórico de métricas no app para iniciar uma nova medição pontual.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
            ],
          },
        };

      case 'tools/call':
        final params = req['params'] as Map<String, dynamic>? ?? {};
        final name = params['name'] as String?;
        final arguments = params['arguments'] as Map<String, dynamic>? ?? {};

        final content = await _executeTool(name, arguments);
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {
                'type': 'text',
                'text': content,
              }
            ],
          },
        };

      default:
        return null;
    }
  }

  Future<String> _executeTool(String? name, Map<String, dynamic> args) async {
    switch (name) {
      case 'get_live_metrics':
        return await _fetchHttpGet('/metrics');

      case 'audit_performance_issues':
        return await _fetchHttpGet('/diagnose');

      case 'get_rebuild_hotspots':
        return await _fetchHttpGet('/rebuilds');

      case 'reset_performance_metrics':
        return await _fetchHttpPost('/reset');

      case 'analyze_performance_log_file':
        final filePath = args['filePath'] as String?;
        if (filePath == null || filePath.isEmpty) {
          return 'Erro: Parâmetro filePath é obrigatório.';
        }
        return await _analyzeLogFile(filePath);

      default:
        return 'Ferramenta desconhecida: $name';
    }
  }

  Future<String> _fetchHttpGet(String endpoint) async {
    try {
      final request = await _httpClient.getUrl(Uri.parse('$devBridgeBaseUrl$endpoint'));
      final response = await request.close().timeout(const Duration(seconds: 3));
      final body = await response.transform(utf8.decoder).join();
      return body;
    } catch (e) {
      return jsonEncode({
        'error': 'Não foi possível conectar ao app Flutter em $devBridgeBaseUrl$endpoint.',
        'details': e.toString(),
        'tip': 'Certifique-se de que o app Flutter está em execução em modo Debug/Profile com o PerformanceOverlay habilitado.',
      });
    }
  }

  Future<String> _fetchHttpPost(String endpoint) async {
    try {
      final request = await _httpClient.postUrl(Uri.parse('$devBridgeBaseUrl$endpoint'));
      final response = await request.close().timeout(const Duration(seconds: 3));
      final body = await response.transform(utf8.decoder).join();
      return body;
    } catch (e) {
      return jsonEncode({
        'error': 'Falha ao enviar requisição para $devBridgeBaseUrl$endpoint.',
        'details': e.toString(),
      });
    }
  }

  Future<String> _analyzeLogFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return jsonEncode({'error': 'Arquivo não encontrado: $filePath'});
      }

      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;

      if (list.isEmpty) {
        return jsonEncode({'error': 'Arquivo de log está vazio.'});
      }

      double totalFps = 0;
      double totalUi = 0;
      double totalRaster = 0;
      double maxRam = 0;
      double maxWorst = 0;
      int highJankCount = 0;

      for (final item in list) {
        final fps = (item['currentFps'] as num?)?.toDouble() ?? 60.0;
        final ui = (item['uiDurationMs'] as num?)?.toDouble() ?? 0.0;
        final raster = (item['rasterDurationMs'] as num?)?.toDouble() ?? 0.0;
        final ram = (item['memoryRssMb'] as num?)?.toDouble() ?? 0.0;
        final worst = (item['worstFrameMs'] as num?)?.toDouble() ?? 0.0;
        final jank = (item['jankPercentage'] as num?)?.toDouble() ?? 0.0;

        totalFps += fps;
        totalUi += ui;
        totalRaster += raster;
        if (ram > maxRam) maxRam = ram;
        if (worst > maxWorst) maxWorst = worst;
        if (jank > 5.0) highJankCount++;
      }

      final avgFps = totalFps / list.length;
      final avgUi = totalUi / list.length;
      final avgRaster = totalRaster / list.length;

      return jsonEncode({
        'totalSamples': list.length,
        'summary': {
          'averageFps': double.parse(avgFps.toStringAsFixed(1)),
          'averageUiDurationMs': double.parse(avgUi.toStringAsFixed(2)),
          'averageRasterDurationMs': double.parse(avgRaster.toStringAsFixed(2)),
          'peakMemoryMb': double.parse(maxRam.toStringAsFixed(1)),
          'worstFrameMs': double.parse(maxWorst.toStringAsFixed(1)),
          'samplesWithHighJank': highJankCount,
        },
        'healthStatus': (avgFps >= 55 && highJankCount == 0) ? 'EXCELLENT' : 'NEEDS_ATTENTION',
      });
    } catch (e) {
      return jsonEncode({'error': 'Falha ao analisar arquivo: $e'});
    }
  }
}
