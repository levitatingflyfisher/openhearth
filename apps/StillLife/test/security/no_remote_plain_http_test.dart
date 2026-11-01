// Guard: no remote endpoint may use plain http.
//
// StillLife keeps usesCleartextTraffic="true" because two features talk to
// devices on the home network, which have no certificate: the Ollama
// home-computer AI and LAN sync. This test makes sure cleartext stays limited
// to those. A new "http://" literal in lib/ fails here until a reviewer adds
// an allowlist entry with a reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'plain_http_scanner.dart';

void main() {
  group('findPlainHttp', () {
    test('flags a remote http URL', () {
      final hits = findPlainHttp(
        'lib/services/x.dart',
        "final u = 'http://api.example.com/v1';",
      );
      expect(hits, hasLength(1));
      expect(hits.single.line, 1);
    });

    test('flags a remote host built from variables in an unlisted file', () {
      final hits = findPlainHttp(
        'lib/services/new_client.dart',
        "final u = 'http://\$host:\$port/x';",
      );
      expect(hits, hasLength(1));
    });

    test('allows a home-network address built from host and port', () {
      final hits = findPlainHttp(
        'lib/services/sync/lan_sync_client.dart',
        "String _baseUrl(String host, int port) => 'http://\$host:\$port';",
      );
      expect(hits, isEmpty);
    });

    test('allows localhost and 127.0.0.1 in any file', () {
      expect(
        findPlainHttp('lib/a.dart', "const a = 'http://localhost:11434';"),
        isEmpty,
      );
      expect(
        findPlainHttp('lib/a.dart', "const a = 'http://127.0.0.1:8080/';"),
        isEmpty,
      );
    });

    test('does not let localhost@evil pass', () {
      final hits = findPlainHttp(
        'lib/a.dart',
        "const a = 'http://localhost.evil.example/';",
      );
      expect(hits, hasLength(1));
    });

    test('skips comment lines', () {
      expect(
        findPlainHttp('lib/a.dart', '/// see http://example.com for notes'),
        isEmpty,
      );
    });
  });

  test('lib/ has no remote plain http literal', () {
    final bad = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final hit in findPlainHttp(
        entity.path,
        entity.readAsStringSync(),
      )) {
        bad.add('${entity.path}:${hit.line}: ${hit.text.trim()}');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'Plain http is only for home-network hosts. Use https, or add an '
          'allowlist entry with a reason in test/security/plain_http_scanner.dart.',
    );
  });
}
