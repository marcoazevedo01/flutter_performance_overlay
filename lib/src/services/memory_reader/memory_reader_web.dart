import 'dart:js_interop';

@JS('window.performance.memory.usedJSHeapSize')
external num? get _usedJSHeapSize;

/// Retorna o consumo de memória heap do JS no navegador (Chromium) em Megabytes.
/// ponytail: browsers baseados em Gecko (Firefox) e WebKit (Safari) não expõem
/// performance.memory por isolamento; nestes casos o retorno será null ('N/A').
double? getPlatformMemoryMb() {
  try {
    final heapBytes = _usedJSHeapSize;
    if (heapBytes != null) {
      return heapBytes.toDouble() / (1024 * 1024);
    }
  } catch (_) {}
  return null;
}
