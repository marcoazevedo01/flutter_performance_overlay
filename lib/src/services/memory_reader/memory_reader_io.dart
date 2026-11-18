import 'dart:convert';
import 'dart:io' show Directory, File, Platform, ProcessInfo, pid;

import 'package:flutter/services.dart';

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

/// Tenta inferir o nome do aplicativo a partir do executável ou diretório atual.
String getPlatformAppName() {
  try {
    final exe = Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last;
    final clean = exe.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
    if (clean.isNotEmpty && clean.toLowerCase() != 'flutter_tester') {
      return clean;
    }
    return Directory.current.path.split(RegExp(r'[/\\]')).last;
  } catch (_) {
    return 'FlutterApp';
  }
}

/// Retorna o sistema operacional e hostname local.
String getPlatformDeviceName() {
  try {
    return '${Platform.operatingSystem} (${Platform.localHostname})';
  } catch (_) {
    return 'Native';
  }
}

/// Detecta automaticamente appName, appVersion e userName do processo/SO sem dependências extras.
Future<Map<String, String?>> getPlatformAppMetadata() async {
  String? appName;
  String? appVersion;
  String? userName;

  try {
    final envUser = Platform.environment['USERNAME'] ?? Platform.environment['USER'];
    if (envUser != null && envUser.trim().isNotEmpty) {
      userName = envUser.trim();
    }
  } catch (_) {}

  // 1. Tenta ler version.json do bundle nativo (Flutter Desktop release/profile/debug)
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final versionFile = File('$exeDir/data/flutter_assets/version.json');
    if (await versionFile.exists()) {
      final json = jsonDecode(await versionFile.readAsString());
      if (json is Map) {
        final name = json['app_name']?.toString().trim();
        final ver = json['version']?.toString().trim();
        final build = json['build_number']?.toString().trim();
        if (name != null && name.isNotEmpty) appName = name;
        if (ver != null && ver.isNotEmpty) {
          appVersion = (build != null && build.isNotEmpty) ? '$ver+$build' : ver;
        }
      }
    }
  } catch (_) {}

  // 2. Fallback para Android/iOS/macOS via canal padrão do package_info_plus (se presente no app)
  if (appVersion == null) {
    try {
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      final info = await channel.invokeMapMethod<String, dynamic>('getAll');
      if (info != null) {
        final name = info['appName']?.toString().trim();
        final ver = info['version']?.toString().trim();
        final build = info['buildNumber']?.toString().trim();
        if (appName == null && name != null && name.isNotEmpty) appName = name;
        if (ver != null && ver.isNotEmpty) {
          appVersion = (build != null && build.isNotEmpty) ? '$ver+$build' : ver;
        }
      }
    } catch (_) {}
  }

  // 3. Fallback em desenvolvimento lendo pubspec.yaml local
  if (appVersion == null) {
    try {
      final pubspec = File('${Directory.current.path}/pubspec.yaml');
      if (await pubspec.exists()) {
        final text = await pubspec.readAsString();
        final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(text);
        final verMatch = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(text);
        if (appName == null && nameMatch != null) {
          appName = nameMatch.group(1)?.trim();
        }
        if (verMatch != null) {
          appVersion = verMatch.group(1)?.trim();
        }
      }
    } catch (_) {}
  }

  return {
    'appName': appName,
    'appVersion': appVersion,
    'userName': userName,
  };
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
