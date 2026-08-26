import 'package:flutter/material.dart';

import '../models/overlay_config.dart';
import '../models/performance_data.dart';
import '../services/performance_monitor_service.dart';
import 'metric_badge.dart';

/// Widget que injeta um overlay flutuante, arrastável e expansível sobre o [child].
class PerformanceOverlayWidget extends StatefulWidget {
  /// Widget filho envolvido pelo overlay (geralmente a raiz do MaterialApp/Router).
  final Widget child;

  /// Serviço de monitoramento. Se omitido, uma instância padrão será criada internamente.
  final PerformanceMonitorService? monitorService;

  /// Configurações de exibição e limites visuais do overlay.
  final PerformanceOverlayConfig config;

  const PerformanceOverlayWidget({
    super.key,
    required this.child,
    this.monitorService,
    this.config = const PerformanceOverlayConfig(),
  });

  @override
  State<PerformanceOverlayWidget> createState() => _PerformanceOverlayWidgetState();
}

class _PerformanceOverlayWidgetState extends State<PerformanceOverlayWidget> {
  final GlobalKey _overlayKey = GlobalKey();
  late PerformanceMonitorService _service;
  late bool _ownsService;
  late final ValueNotifier<PerformanceData> _dataNotifier;

  late Offset _position;
  late bool _isExpanded;
  Size _overlaySize = const Size(120, 32);

  @override
  void initState() {
    super.initState();
    _position = widget.config.initialPosition;
    _isExpanded = widget.config.startExpanded;

    if (widget.monitorService != null) {
      _service = widget.monitorService!;
      _ownsService = false;
    } else {
      _service = PerformanceMonitorService();
      _ownsService = true;
    }

    _dataNotifier = ValueNotifier<PerformanceData>(_service.lastData);

    if (widget.config.enabled) {
      _service.onMetricsUpdated = (data) {
        _dataNotifier.value = data;
      };
      _service.start();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverlaySizeAndClamp());
  }

  @override
  void didUpdateWidget(PerformanceOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config.enabled != oldWidget.config.enabled) {
      if (widget.config.enabled) {
        _service.start();
      } else {
        _service.stop();
      }
    }
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    _dataNotifier.dispose();
    super.dispose();
  }

  void _updateOverlaySizeAndClamp() {
    if (!mounted) return;
    final renderBox = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      _overlaySize = renderBox.size;
    }
    _clampPositionToScreen();
  }

  void _clampPositionToScreen() {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return;

    final screenSize = mediaQuery.size;
    final padding = widget.config.keepWithinSafeArea ? mediaQuery.padding : EdgeInsets.zero;

    final minX = padding.left;
    final maxX = (screenSize.width - padding.right - _overlaySize.width).clamp(minX, screenSize.width);
    final minY = padding.top;
    final maxY = (screenSize.height - padding.bottom - _overlaySize.height).clamp(minY, screenSize.height);

    final clampedX = _position.dx.clamp(minX, maxX);
    final clampedY = _position.dy.clamp(minY, maxY);

    if (clampedX != _position.dx || clampedY != _position.dy) {
      setState(() {
        _position = Offset(clampedX, clampedY);
      });
    }
  }

  Color _getFpsColor(double fps) {
    if (fps >= widget.config.goodFpsThreshold) return widget.config.goodFpsColor;
    if (fps >= widget.config.warningFpsThreshold) return widget.config.warningFpsColor;
    return widget.config.badFpsColor;
  }

  Color _getDurationColor(double durationMs) {
    if (durationMs <= 8.3) return const Color(0xFF4CAF50);
    if (durationMs <= 16.6) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  Color _getJankColor(double jankPercentage) {
    if (jankPercentage <= 1.0) return const Color(0xFF4CAF50);
    if (jankPercentage <= 5.0) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  Color _getDeltaRamColor(double deltaMb) {
    if (deltaMb > 1.0) return const Color(0xFFFF9800);
    if (deltaMb < 0.0) return const Color(0xFF81C784);
    return Colors.white70;
  }

  Color _getLagColor(double lagMs) {
    if (lagMs <= 15.0) return const Color(0xFF4CAF50);
    if (lagMs <= 50.0) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.enabled) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              final mediaQuery = MediaQuery.maybeOf(context);
              if (mediaQuery == null) {
                setState(() => _position += details.delta);
                return;
              }

              final screenSize = mediaQuery.size;
              final padding = widget.config.keepWithinSafeArea ? mediaQuery.padding : EdgeInsets.zero;

              final minX = padding.left;
              final maxX = (screenSize.width - padding.right - _overlaySize.width).clamp(minX, screenSize.width);
              final minY = padding.top;
              final maxY = (screenSize.height - padding.bottom - _overlaySize.height).clamp(minY, screenSize.height);

              final newX = (_position.dx + details.delta.dx).clamp(minX, maxX);
              final newY = (_position.dy + details.delta.dy).clamp(minY, maxY);

              setState(() {
                _position = Offset(newX, newY);
              });
            },
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverlaySizeAndClamp());
            },
            child: Material(
              type: MaterialType.transparency,
              child: ValueListenableBuilder<PerformanceData>(
                valueListenable: _dataNotifier,
                builder: (context, data, _) {
                  return Container(
                    key: _overlayKey,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.config.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24, width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isExpanded
                        ? _buildExpandedContent(data)
                        : _buildCompactContent(data),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactContent(PerformanceData data) {
    final cfg = widget.config;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cfg.showFps)
          MetricBadge(
            label: 'FPS',
            value: data.currentFps.toStringAsFixed(0),
            valueColor: _getFpsColor(data.currentFps),
            fontSize: cfg.fontSize,
          ),
        if (cfg.showMemory) ...[
          const SizedBox(width: 4),
          MetricBadge(
            label: 'RAM',
            value: '${data.memoryRssMb.toStringAsFixed(0)}MB',
            valueColor: const Color(0xFF64B5F6),
            fontSize: cfg.fontSize,
          ),
        ],
        const SizedBox(width: 4),
        Icon(
          Icons.unfold_more,
          size: cfg.fontSize + 2,
          color: Colors.white38,
        ),
      ],
    );
  }

  Widget _buildExpandedContent(PerformanceData data) {
    final cfg = widget.config;
    final deltaSign = data.deltaMemoryRssMb >= 0 ? '+' : '';
    final deltaStr = '$deltaSign${data.deltaMemoryRssMb.toStringAsFixed(1)}MB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Linha 1: FPS e Médias
        if (cfg.showFps)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MetricBadge(
                label: 'FPS',
                value: data.currentFps.toStringAsFixed(0),
                valueColor: _getFpsColor(data.currentFps),
                fontSize: cfg.fontSize,
              ),
              MetricBadge(
                label: 'AVG',
                value: data.averageFps.toStringAsFixed(1),
                valueColor: Colors.white70,
                fontSize: cfg.fontSize,
              ),
            ],
          ),

        // Linha 2: UI Build & GPU Raster
        if (cfg.showUiRasterTiming)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MetricBadge(
                label: 'UI',
                value: '${data.uiDurationMs.toStringAsFixed(1)}ms',
                valueColor: _getDurationColor(data.uiDurationMs),
                fontSize: cfg.fontSize,
              ),
              MetricBadge(
                label: 'GPU',
                value: '${data.rasterDurationMs.toStringAsFixed(1)}ms',
                valueColor: _getDurationColor(data.rasterDurationMs),
                fontSize: cfg.fontSize,
              ),
            ],
          ),

        // Linha 3: Jank e Pior Frame
        if (cfg.showJankRate)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MetricBadge(
                label: 'Jank',
                value: '${data.jankPercentage.toStringAsFixed(1)}%',
                valueColor: _getJankColor(data.jankPercentage),
                fontSize: cfg.fontSize,
              ),
              MetricBadge(
                label: 'Max',
                value: '${data.worstFrameMs.toStringAsFixed(1)}ms',
                valueColor: _getDurationColor(data.worstFrameMs),
                fontSize: cfg.fontSize,
              ),
            ],
          ),

        // Linha 4: Memória, Delta RAM e Pico
        if (cfg.showMemory)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MetricBadge(
                label: 'RAM',
                value: '${data.memoryRssMb.toStringAsFixed(1)}MB',
                valueColor: const Color(0xFF64B5F6),
                fontSize: cfg.fontSize,
              ),
              if (cfg.showDeltaMemory)
                MetricBadge(
                  label: 'ΔRAM',
                  value: deltaStr,
                  valueColor: _getDeltaRamColor(data.deltaMemoryRssMb),
                  fontSize: cfg.fontSize,
                ),
              if (cfg.showPeakMemory)
                MetricBadge(
                  label: 'Pico',
                  value: '${data.peakMemoryRssMb.toStringAsFixed(1)}MB',
                  valueColor: const Color(0xFF90CAF9),
                  fontSize: cfg.fontSize,
                ),
            ],
          ),

        // Linha 5: Rota Atual e Rebuilds
        if (cfg.showCurrentRoute || cfg.showRebuildCount)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cfg.showCurrentRoute)
                MetricBadge(
                  label: 'Rota',
                  value: data.currentRoute,
                  valueColor: const Color(0xFFFFD54F),
                  fontSize: cfg.fontSize,
                ),
              if (cfg.showRebuildCount)
                MetricBadge(
                  label: 'Rebuilds',
                  value: '${data.rebuildCount}',
                  valueColor: const Color(0xFF80CBC4),
                  fontSize: cfg.fontSize,
                ),
            ],
          ),

        // Linha 6: Event Loop Lag / UI Freeze Detector
        if (cfg.showEventLoopLag)
          MetricBadge(
            label: 'Event Loop Freeze',
            value: data.eventLoopLagMs > 5.0
                ? '+${data.eventLoopLagMs.toStringAsFixed(0)}ms (LAG)'
                : '0ms (OK)',
            valueColor: _getLagColor(data.eventLoopLagMs),
            fontSize: cfg.fontSize,
          ),
      ],
    );
  }
}
