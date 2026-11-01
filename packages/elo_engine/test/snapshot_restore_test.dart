import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

EloEngine _played() {
  final engine = EloEngine(
      items: [EloItem(id: 'a'), EloItem(id: 'b'), EloItem(id: 'c')]);
  engine.record('a', 'b', MatchOutcome.aWins);
  engine.record('b', 'c', MatchOutcome.aWins);
  engine.record('a', 'c', MatchOutcome.aWins);
  engine.record('c', 'a', MatchOutcome.tie);
  return engine;
}

void main() {
  group('fromJson skipReplay with an incomplete snapshot', () {
    test('Glicko-2 and TrueSkill state is rebuilt, not reset', () {
      final original = _played();
      final json = original.toJson();
      (json['glicko2'] as Map).remove('c');
      (json['trueskill'] as Map).remove('c');

      final restored = EloEngine.fromJson(json, skipReplay: true);
      final out = restored.toJson();
      final want = original.toJson();
      expect(out['glicko2'], equals(want['glicko2']));
      expect(out['trueskill'], equals(want['trueskill']));
      // The ELO ratings still come from the stored items, as before.
      for (final item in original.items) {
        final r = restored.items.firstWhere((i) => i.id == item.id);
        expect(r.rating, closeTo(item.rating, 0.001));
      }
    });

    test('a complete snapshot is still restored as stored', () {
      final original = _played();
      final restored =
          EloEngine.fromJson(original.toJson(), skipReplay: true);
      expect(restored.toJson()['glicko2'], equals(original.toJson()['glicko2']));
      expect(
          restored.toJson()['trueskill'], equals(original.toJson()['trueskill']));
    });
  });
}
