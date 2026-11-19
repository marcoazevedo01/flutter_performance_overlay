import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';
import 'package:flutter_performance_overlay/src/services/remote_relay/remote_relay_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteRelayProtocol Security Tests', () {
    test('buildUri preserves URL without appending key query parameter', () {
      final uri = RemoteRelayProtocol.buildUri('wss://socket.example.com/perf-ws');
      expect(uri.scheme, 'wss');
      expect(uri.path, '/perf-ws');
      expect(uri.queryParameters.containsKey('key'), isFalse);
    });

    test('buildAuthPayload builds auth frame for authToken or relayKey', () {
      expect(
        RemoteRelayProtocol.buildAuthPayload(authToken: 'jwt.abc.def'),
        {'type': 'auth', 'authToken': 'jwt.abc.def'},
      );
      expect(
        RemoteRelayProtocol.buildAuthPayload(relayKey: 'relay-secret'),
        {'type': 'auth', 'key': 'relay-secret'},
      );
      expect(
        RemoteRelayProtocol.buildAuthPayload(relayKey: '', authToken: ''),
        isNull,
      );
      expect(RemoteRelayProtocol.buildAuthPayload(), isNull);
    });
  });

  group('Log & Error Sanitization Tests', () {
    test('sanitizeText redacts bearer tokens, headers, secrets and CPF/CNPJ', () {
      const sample =
          'GET /api Authorization: Bearer eyJhbGciOi.123.abc-DEF '
          '{"token":"tok123","access_token":"acc123","refresh_token":"ref123",'
          '"senha":"segredo","password":"pw1","secret":"s1","apiKey":"k1"} '
          'api_key=abc123 x-perf-key: mykey cpf: 123.456.789-00 cnpj=12.345.678/0001-99';

      final sanitized = PerformanceMonitorService.sanitizeText(sample);

      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, isNot(contains('eyJhbGciOi.123.abc-DEF')));
      expect(sanitized, isNot(contains('tok123')));
      expect(sanitized, isNot(contains('acc123')));
      expect(sanitized, isNot(contains('ref123')));
      expect(sanitized, isNot(contains('segredo')));
      expect(sanitized, isNot(contains('pw1')));
      expect(sanitized, isNot(contains('"s1"')));
      expect(sanitized, isNot(contains('"k1"')));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('mykey')));
      expect(sanitized, isNot(contains('123.456.789-00')));
      expect(sanitized, isNot(contains('12.345.678/0001-99')));
      expect(sanitized, contains('[REDACTED]'));
      expect(sanitized, contains('[REDACTED_CPF]'));
      expect(sanitized, contains('[REDACTED_CNPJ]'));
    });

    test('sanitizeText truncates payloads over 8192 characters', () {
      final longInput = 'A' * 9000;
      final sanitized = PerformanceMonitorService.sanitizeText(longInput);
      expect(sanitized.endsWith('... [truncated]'), isTrue);
      expect(sanitized.length, lessThanOrEqualTo(8192 + '... [truncated]'.length));
    });

    test('startStreaming sanitizes captured debugPrint logs by default', () {
      final service = PerformanceMonitorService(
        enableDevBridge: false,
        enableServiceExtensions: false,
      );
      addTearDown(service.dispose);

      service.startStreaming(onChunk: (_) {});
      debugPrint('HTTP header Authorization: Bearer super-secret-jwt cpf 111.222.333-44');
      final finalChunk = service.stopStreaming();

      final logs = finalChunk['logs'] as List;
      expect(logs, isNotEmpty);
      final msg = logs.last['message'] as String;
      expect(msg, isNot(contains('super-secret-jwt')));
      expect(msg, isNot(contains('111.222.333-44')));
      expect(msg, contains('[REDACTED]'));
      expect(msg, contains('[REDACTED_CPF]'));
    });

    test('OverlayConfig defaults match hardened security settings', () {
      const config = PerformanceOverlayConfig();
      expect(config.enableDevBridge, kDebugMode);
      expect(config.sanitizeLogs, isTrue);
    });
  });

  group('PerformanceDevBridge CORS Security Tests', () {
    late PerformanceMonitorService monitorService;
    late PerformanceDevBridge devBridge;
    const testPort = 8798;

    setUp(() async {
      HttpOverrides.global = null;
      monitorService = PerformanceMonitorService(
        enableDevBridge: false,
        enableServiceExtensions: false,
      );
      devBridge = PerformanceDevBridge(
        port: testPort,
        monitorService: monitorService,
      );
      await devBridge.start();
    });

    tearDown(() async {
      await devBridge.stop();
      monitorService.dispose();
    });

    test('rejects untrusted external Origin with 403 and no CORS header', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/health'));
        req.headers.set('Origin', 'https://evil.example');
        final res = await req.close();
        expect(res.statusCode, HttpStatus.forbidden);
        expect(res.headers.value('access-control-allow-origin'), isNull);
        final body = await res.transform(utf8.decoder).join();
        expect(jsonDecode(body)['error'], 'Origin not allowed');
      } finally {
        client.close();
      }
    });

    test('allows localhost Origin and echoes exact Origin', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/health'));
        req.headers.set('Origin', 'http://localhost:3000');
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(res.headers.value('access-control-allow-origin'), 'http://localhost:3000');
        expect(res.headers.value('vary'), contains('Origin'));
      } finally {
        client.close();
      }
    });

    test('allows requests without Origin without wildcard CORS header', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/health'));
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        expect(res.headers.value('access-control-allow-origin'), isNull);
      } finally {
        client.close();
      }
    });
  });
}
