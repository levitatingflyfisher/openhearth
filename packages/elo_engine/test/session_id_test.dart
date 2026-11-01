import 'package:elo_engine/elo_engine.dart';
import 'package:test/test.dart';

/// The session-id generator must work on every shipped target, including
/// dart2js (Mantle and Lilt ship web PWAs). Run this file on a JS platform
/// too: `dart test -p node test/session_id_test.dart`.
void main() {
  group('EloSession auto-generated sessionId', () {
    test('does not throw and has the session_<ms>_<base36> shape', () {
      for (var i = 0; i < 200; i++) {
        final s = EloSession(items: const [], history: const []);
        expect(s.sessionId, matches(RegExp(r'^session_\d+_[0-9a-z]+$')));
      }
    });

    test('ids are not all identical (random part varies)', () {
      final ids = {
        for (var i = 0; i < 50; i++)
          EloSession(items: const [], history: const []).sessionId,
      };
      expect(ids.length, greaterThan(1));
    });
  });
}
