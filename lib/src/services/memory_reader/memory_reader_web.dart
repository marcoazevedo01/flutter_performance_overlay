import 'dart:js_interop';

@JS('window.performance.memory.usedJSHeapSize')
external num? get _usedJSHeapSize;

@JS('window.__fpoBaselineMemoryMb')
external num? get _windowBaselineMb;

@JS('window.__fpoBaselineMemoryMb')
external set _windowBaselineMb(num? value);

double? _emaMemoryMb;
double? _webBaselineMb;

/// ponytail: Fator de amortecimento EMA (0.2) para filtrar oscilações transitórias de GC do Chromium no JS Heap.
const double _alpha = 0.2;

/// Retorna o consumo de memória heap do JS no navegador (Chromium) em Megabytes suavizado por EMA.
/// ponytail: browsers baseados em Gecko (Firefox) e WebKit (Safari) não expõem
/// performance.memory por isolamento; nestes casos o retorno será null ('N/A').
double? getPlatformMemoryMb() {
  try {
    final heapBytes = _usedJSHeapSize;
    if (heapBytes != null) {
      final rawMb = heapBytes.toDouble() / (1024 * 1024);
      if (_emaMemoryMb == null) {
        _emaMemoryMb = rawMb;
      } else {
        _emaMemoryMb = (_alpha * rawMb) + ((1.0 - _alpha) * _emaMemoryMb!);
      }
      return _emaMemoryMb;
    }
  } catch (_) {}
  return null;
}

/// Obtém ou define o baseline inicial de memória no objeto global `window` (sobrevive ao Hot Restart do DDC).
double getOrSetProcessBaselineMemoryMb(double currentMb) {
  if (_webBaselineMb != null) return _webBaselineMb!;
  try {
    final existing = _windowBaselineMb;
    if (existing != null && existing > 0) {
      _webBaselineMb = existing.toDouble();
      return _webBaselineMb!;
    }
    _windowBaselineMb = currentMb;
  } catch (_) {}
  _webBaselineMb = currentMb;
  return currentMb;
}

/// Redefine o baseline de memória armazenado em `window` e no cache local.
void resetProcessBaselineMemoryMb([double? currentMb]) {
  _webBaselineMb = currentMb;
  try {
    _windowBaselineMb = currentMb;
  } catch (_) {}
}
