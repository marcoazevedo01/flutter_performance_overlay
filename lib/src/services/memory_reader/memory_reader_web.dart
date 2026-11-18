import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

@JS('document.title')
external String? get _documentTitle;

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

/// Retorna o título do documento HTML ou fallback para identificar o app Web.
String getPlatformAppName() {
  try {
    final title = _documentTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
  } catch (_) {}
  return 'FlutterWeb';
}

/// Identifica a plataforma como navegador Web.
String getPlatformDeviceName() => 'Web Browser';

/// Detecta automaticamente appName e appVersion no Flutter Web via version.json ou package_info.
Future<Map<String, String?>> getPlatformAppMetadata() async {
  String? appName;
  String? appVersion;

  try {
    final resp = await http
        .get(Uri.base.resolve('version.json'))
        .timeout(const Duration(seconds: 3));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
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

  return {
    'appName': appName,
    'appVersion': appVersion,
    'userName': null,
  };
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
