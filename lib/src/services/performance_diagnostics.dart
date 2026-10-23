import '../models/performance_data.dart';
import 'rebuild_tracker.dart';

/// Nível de severidade de um problema de performance detectado.
enum DiagnosticSeverity { info, warning, critical }

/// Representa um problema de desempenho diagnosticado.
class DiagnosticIssue {
  final String title;
  final String description;
  final DiagnosticSeverity severity;
  final String suggestion;

  const DiagnosticIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.suggestion,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'severity': severity.name,
        'suggestion': suggestion,
      };
}

/// Motor de diagnóstico automático para analisar métricas e apontar anomalias.
class PerformanceDiagnostics {
  /// Analisa um conjunto de dados recentes e retorna a lista de problemas encontrados.
  static List<DiagnosticIssue> analyze({
    required PerformanceData currentData,
    required List<PerformanceData> history,
    Map<String, int>? rebuildsByWidget,
  }) {
    final issues = <DiagnosticIssue>[];

    // 1. Diagnóstico de FPS e Jank
    if (currentData.currentFps < 30.0 || currentData.averageFps < 45.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Baixa Taxa de Quadros (Low FPS)',
          description:
              'FPS atual: ${currentData.currentFps.toStringAsFixed(1)} (Média: ${currentData.averageFps.toStringAsFixed(1)} FPS).',
          severity: currentData.currentFps < 25.0
              ? DiagnosticSeverity.critical
              : DiagnosticSeverity.warning,
          suggestion:
              'Verifique se listas estão utilizando ListView.builder e evite recálculos pesados no método build.',
        ),
      );
    }

    if (currentData.jankPercentage > 5.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Taxa Excessiva de Frames Perdidos (Jank)',
          description:
              '${currentData.jankPercentage.toStringAsFixed(1)}% dos frames recentes ultrapassaram o orçamento de 16.6ms. Pior frame: ${currentData.worstFrameMs.toStringAsFixed(1)}ms.',
          severity: currentData.jankPercentage > 15.0
              ? DiagnosticSeverity.critical
              : DiagnosticSeverity.warning,
          suggestion:
              'Utilize RepaintBoundary para isolar áreas com animações constantes e evite Opacity em árvores complexas.',
        ),
      );
    }

    // 2. Gargalo de UI Thread vs GPU/Raster Thread
    if (currentData.uiDurationMs > 12.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Gargalo na UI Thread (Dart Build Duration)',
          description:
              'Tempo médio de build na UI thread: ${currentData.uiDurationMs.toStringAsFixed(1)}ms (ideal: < 8ms).',
          severity: currentData.uiDurationMs > 16.0
              ? DiagnosticSeverity.critical
              : DiagnosticSeverity.warning,
          suggestion:
              'Mova parsing de JSON, ordenação de listas ou criptografia para Isolates (compute / Isolate.run).',
        ),
      );
    }

    if (currentData.rasterDurationMs > 12.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Gargalo na Raster/GPU Thread (Render Duration)',
          description:
              'Tempo médio de rasterização/desenho na GPU: ${currentData.rasterDurationMs.toStringAsFixed(1)}ms.',
          severity: currentData.rasterDurationMs > 16.0
              ? DiagnosticSeverity.critical
              : DiagnosticSeverity.warning,
          suggestion:
              'Evite BackdropFilter, ClipRRect aninhados em excesso e garanta que imagens estejam com cacheWidth/cacheHeight definidos.',
        ),
      );
    }

    // 3. Detecção de Congelamento do Event Loop (UI Freeze)
    if (currentData.eventLoopLagMs > 50.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Bloqueio Síncrono no Event Loop (UI Freeze)',
          description:
              'Atraso detectado na fila de eventos: +${currentData.eventLoopLagMs.toStringAsFixed(0)}ms.',
          severity: currentData.eventLoopLagMs > 150.0
              ? DiagnosticSeverity.critical
              : DiagnosticSeverity.warning,
          suggestion:
              'Existe código síncrono bloqueando a execução do Dart. Remova loops pesados ou I/O síncrono da thread principal.',
        ),
      );
    }

    // 4. Suspeita de Vazamento de Memória (Memory Leak)
    if (currentData.memoryRssMb >= 0 && currentData.deltaMemoryRssMb > 5.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Crescimento Acentuado de Memória (Taxa ΔRAM Elevada)',
          description:
              'Taxa de alocação de +${currentData.deltaMemoryRssMb.toStringAsFixed(1)}MB/s na memória (Total: ${currentData.memoryRssMb.toStringAsFixed(1)}MB).',
          severity: DiagnosticSeverity.warning,
          suggestion:
              'Verifique carregamento massivo de imagens, buffers ou decodificação síncrona na UI thread.',
        ),
      );
    }

    if (currentData.memoryRssMb >= 0 && currentData.routeDeltaMemoryMb > 15.0) {
      issues.add(
        DiagnosticIssue(
          title: 'Possível Vazamento na Rota Ativa: <${currentData.currentRoute}>',
          description:
              'A tela "${currentData.currentRoute}" acumulou +${currentData.routeDeltaMemoryMb.toStringAsFixed(1)}MB desde que foi aberta.',
          severity: DiagnosticSeverity.warning,
          suggestion:
              'Verifique se Streams, Listeners ou Controllers estão sendo liberados no dispose() desta rota.',
        ),
      );
    }

    // 5. Hotspots de Rebuilds
    final rebuilds = rebuildsByWidget ?? PerformanceRebuildTracker().rebuildsByWidget;
    for (final entry in rebuilds.entries) {
      if (entry.value > 50) {
        issues.add(
          DiagnosticIssue(
            title: 'Hotspot de Reconstrução: <${entry.key}>',
            description:
                'O widget "${entry.key}" foi reconstruído ${entry.value} vezes nesta sessão.',
            severity: entry.value > 150
                ? DiagnosticSeverity.critical
                : DiagnosticSeverity.warning,
            suggestion:
                'Adicione const constructors, use Selectors/BlocSelectors granulares ou quebre o widget em componentes menores.',
          ),
        );
      }
    }

    return issues;
  }
}
