import 'dart:io' show Directory, File, ProcessInfo, pid;

double? _cachedBaselineMb;

File _baselineFile() =>
    File('${Directory.systemTemp.path}/fpo_baseline_$pid.tmp');

/// Retorna o consumo de memória RSS nativo do processo em Megabytes.
double? getPlatformMemoryMb() {
  try {
    return ProcessInfo.currentRss / (1024 * 1024);
  } catch (_) {
    return null;
  }
}

/// ponytail: Persiste o baseline inicial no temp por PID para sobreviver ao Hot Restart
/// (que zera o Isolate do Dart mas mantém o mesmo processo do SO), com cache em RAM para zero I/O por tick.
double getOrSetProcessBaselineMemoryMb(double currentMb) {
  if (_cachedBaselineMb != null) return _cachedBaselineMb!;
  try {
    final file = _baselineFile();
    if (file.existsSync()) {
      final parsed = double.tryParse(file.readAsStringSync().trim());
      if (parsed != null && parsed > 0) {
        _cachedBaselineMb = parsed;
        return parsed;
      }
    }
    file.writeAsStringSync(currentMb.toStringAsFixed(2), flush: true);
  } catch (_) {}
  _cachedBaselineMb = currentMb;
  return currentMb;
}

/// Redefine o baseline de memória do processo no cache e no arquivo temporário do PID.
void resetProcessBaselineMemoryMb([double? currentMb]) {
  _cachedBaselineMb = currentMb;
  try {
    final file = _baselineFile();
    if (currentMb != null && currentMb > 0) {
      file.writeAsStringSync(currentMb.toStringAsFixed(2), flush: true);
    } else if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (_) {}
}
