import 'package:flutter/material.dart';

/// Configuração visual e funcional do overlay de desempenho.
class PerformanceOverlayConfig {
  /// Se o overlay e a coleta de métricas estão ativos.
  final bool enabled;

  /// Exibir indicador de FPS instantâneo e médio.
  final bool showFps;

  /// Exibir tempos de execução da UI Thread e GPU/Raster Thread.
  final bool showUiRasterTiming;

  /// Exibir taxa de quadros perdidos (Jank %).
  final bool showJankRate;

  /// Exibir consumo de memória RAM RSS.
  final bool showMemory;

  /// Exibir taxa de variação de memória RAM (Delta RAM).
  final bool showDeltaMemory;

  /// Exibir variação de memória RAM acumulada na rota ativa.
  final bool showRouteDeltaMemory;

  /// Exibir pico máximo de memória atingido na sessão.
  final bool showPeakMemory;

  /// Exibir indicador de atraso no Event Loop do Dart / UI Freeze.
  final bool showEventLoopLag;

  /// Exibir a rota/tela atual ativa na navegação.
  final bool showCurrentRoute;

  /// Exibir a contagem total de rebuilds rastreados.
  final bool showRebuildCount;

  /// Restringir o posicionamento do overlay para respeitar a SafeArea (evita entalhes/status bar).
  final bool keepWithinSafeArea;

  /// Habilita o mini-servidor HTTP local (DevBridge) para integração com agentes de IA (MCP) e inspeção.
  final bool enableDevBridge;

  /// Porta do servidor local DevBridge (padrão: 8765).
  final int devBridgePort;

  /// Posição inicial do overlay na tela.
  final Offset initialPosition;

  /// Se o overlay deve iniciar no modo expandido ou compacto.
  final bool startExpanded;

  /// Limite de FPS considerado excelente (verde). Padrão: 55.0.
  final double goodFpsThreshold;

  /// Limite de FPS considerado aceitável antes de alertar (laranja). Padrão: 30.0.
  final double warningFpsThreshold;

  /// Cor para FPS acima de [goodFpsThreshold].
  final Color goodFpsColor;

  /// Cor para FPS entre [warningFpsThreshold] e [goodFpsThreshold].
  final Color warningFpsColor;

  /// Cor para FPS abaixo de [warningFpsThreshold].
  final Color badFpsColor;

  /// Cor de fundo do painel do overlay.
  final Color backgroundColor;

  /// Tamanho da fonte dos textos de métricas.
  final double fontSize;

  const PerformanceOverlayConfig({
    this.enabled = true,
    this.showFps = true,
    this.showUiRasterTiming = true,
    this.showJankRate = true,
    this.showMemory = true,
    this.showDeltaMemory = true,
    this.showRouteDeltaMemory = true,
    this.showPeakMemory = true,
    this.showEventLoopLag = true,
    this.showCurrentRoute = true,
    this.showRebuildCount = true,
    this.keepWithinSafeArea = true,
    this.enableDevBridge = true,
    this.devBridgePort = 8765,
    this.initialPosition = const Offset(16, 50),
    this.startExpanded = false,
    this.goodFpsThreshold = 55.0,
    this.warningFpsThreshold = 30.0,
    this.goodFpsColor = const Color(0xFF4CAF50),
    this.warningFpsColor = const Color(0xFFFF9800),
    this.badFpsColor = const Color(0xFFF44336),
    this.backgroundColor = const Color(0xDD1E1E1E),
    this.fontSize = 11.0,
  });

  PerformanceOverlayConfig copyWith({
    bool? enabled,
    bool? showFps,
    bool? showUiRasterTiming,
    bool? showJankRate,
    bool? showMemory,
    bool? showDeltaMemory,
    bool? showRouteDeltaMemory,
    bool? showPeakMemory,
    bool? showEventLoopLag,
    bool? showCurrentRoute,
    bool? showRebuildCount,
    bool? keepWithinSafeArea,
    bool? enableDevBridge,
    int? devBridgePort,
    Offset? initialPosition,
    bool? startExpanded,
    double? goodFpsThreshold,
    double? warningFpsThreshold,
    Color? goodFpsColor,
    Color? warningFpsColor,
    Color? badFpsColor,
    Color? backgroundColor,
    double? fontSize,
  }) {
    return PerformanceOverlayConfig(
      enabled: enabled ?? this.enabled,
      showFps: showFps ?? this.showFps,
      showUiRasterTiming: showUiRasterTiming ?? this.showUiRasterTiming,
      showJankRate: showJankRate ?? this.showJankRate,
      showMemory: showMemory ?? this.showMemory,
      showDeltaMemory: showDeltaMemory ?? this.showDeltaMemory,
      showRouteDeltaMemory: showRouteDeltaMemory ?? this.showRouteDeltaMemory,
      showPeakMemory: showPeakMemory ?? this.showPeakMemory,
      showEventLoopLag: showEventLoopLag ?? this.showEventLoopLag,
      showCurrentRoute: showCurrentRoute ?? this.showCurrentRoute,
      showRebuildCount: showRebuildCount ?? this.showRebuildCount,
      keepWithinSafeArea: keepWithinSafeArea ?? this.keepWithinSafeArea,
      enableDevBridge: enableDevBridge ?? this.enableDevBridge,
      devBridgePort: devBridgePort ?? this.devBridgePort,
      initialPosition: initialPosition ?? this.initialPosition,
      startExpanded: startExpanded ?? this.startExpanded,
      goodFpsThreshold: goodFpsThreshold ?? this.goodFpsThreshold,
      warningFpsThreshold: warningFpsThreshold ?? this.warningFpsThreshold,
      goodFpsColor: goodFpsColor ?? this.goodFpsColor,
      warningFpsColor: warningFpsColor ?? this.warningFpsColor,
      badFpsColor: badFpsColor ?? this.badFpsColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}
