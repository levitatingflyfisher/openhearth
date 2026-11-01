// Canonical JSON (BUILD-SPEC §3: "Canonical JSON (sorted keys, no whitespace)
// is the signing/encryption input everywhere.") — determinism is what makes
// signatures verifiable, so this module is tested before anything signs.
import 'dart:convert';

import 'package:porch_app/domain/support/canonical_json.dart';
import 'package:test/test.dart';

void main() {
  group('canonicalJson', () {
    test('sorts keys recursively and emits no whitespace', () {
      final s = canonicalJson({
        'zeta': 1,
        'alpha': {'b': 2, 'a': 1},
        'mid': [
          {'y': true, 'x': null},
        ],
      });
      expect(s, '{"alpha":{"a":1,"b":2},"mid":[{"x":null,"y":true}],"zeta":1}');
    });

    test('is deterministic regardless of insertion order', () {
      final a = canonicalJson({'a': 1, 'b': 2, 'c': 3});
      final b = canonicalJson({'c': 3, 'a': 1, 'b': 2});
      expect(a, b);
    });

    test('round-trips through jsonDecode', () {
      final original = {
        'v': 1,
        'type': 'presence',
        'tag': '🚶 walking',
        'nested': ['a', 2, false],
      };
      final decoded = jsonDecode(canonicalJson(original));
      expect(decoded, original);
    });

    test('escapes strings the way jsonDecode expects', () {
      final s = canonicalJson({'k': 'line\nbreak "quoted" \\ slash'});
      expect(jsonDecode(s), {'k': 'line\nbreak "quoted" \\ slash'});
    });

    test('canonicalJsonBytes is utf8 of canonicalJson', () {
      final m = {'emoji': '🧹'};
      expect(canonicalJsonBytes(m), utf8.encode(canonicalJson(m)));
    });

    test('rejects doubles — the wire protocol is integer-only', () {
      expect(() => canonicalJson({'x': 1.5}), throwsArgumentError);
    });

    test('rejects non-string map keys', () {
      expect(() => canonicalJson({1: 'x'}), throwsArgumentError);
    });

    test('rejects unsupported object types', () {
      expect(() => canonicalJson({'x': DateTime.now()}), throwsArgumentError);
    });
  });
}
