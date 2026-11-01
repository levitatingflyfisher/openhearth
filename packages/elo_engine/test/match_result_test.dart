import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  group('MatchResult deltaA', () {
    test('B change is not -deltaA when the K-factors differ', () {
      final engine = EloEngine(
          items: [EloItem(id: 'a'), EloItem(id: 'b'), EloItem(id: 'c')]);
      // a and b reach 10 matches, so their K drops to 32. c is new, K 64.
      for (var i = 0; i < 10; i++) {
        engine.record('a', 'b', MatchOutcome.tie);
      }
      final c = engine.items.firstWhere((i) => i.id == 'c');
      final before = c.rating;
      final result = engine.record('a', 'c', MatchOutcome.aWins);
      final deltaB = c.rating - before;
      expect(deltaB, isNot(closeTo(-result.deltaA, 1e-9)));
      // c's K is twice a's, so its change is twice as large.
      expect(deltaB, closeTo(-2 * result.deltaA, 1e-9));
    });
  });
}
