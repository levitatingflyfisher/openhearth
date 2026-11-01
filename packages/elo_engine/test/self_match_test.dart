import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  group('record self-match guard', () {
    test('an item matched with itself throws and changes nothing', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      expect(() => engine.record('a', 'a', MatchOutcome.aWins),
          throwsArgumentError);
      expect(engine.history, isEmpty);
      final a = engine.items.firstWhere((i) => i.id == 'a');
      expect(a.rating, 1200.0);
      expect(a.matchCount, 0);
    });

    test('a skip of an item with itself is also refused', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      expect(() => engine.record('a', 'a', MatchOutcome.skip),
          throwsArgumentError);
      expect(engine.history, isEmpty);
    });
  });
}
