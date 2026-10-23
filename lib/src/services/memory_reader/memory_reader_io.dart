import 'dart:io' show ProcessInfo;

/// Retorna o consumo de memória RSS nativo do processo em Megabytes.
double? getPlatformMemoryMb() {
  try {
    return ProcessInfo.currentRss / (1024 * 1024);
  } catch (_) {
    return null;
  }
}
