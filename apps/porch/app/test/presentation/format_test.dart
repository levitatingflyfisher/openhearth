// W4: time formatting for the feed — countdowns and the honesty line.
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/format.dart';

void main() {
  group('formatRemaining (countdown from expiresAt — §3.4 step 6)', () {
    test('minutes under an hour', () {
      expect(formatRemaining(42 * 60), '42 min left');
      expect(formatRemaining(60), '1 min left');
    });
    test('partial minutes round UP — never claim less time than there is... '
        'wait, never claim MORE: 61 s is "2 min" is a lie; show 1 min', () {
      expect(formatRemaining(61), '1 min left');
      expect(formatRemaining(119), '1 min left');
    });
    test('under a minute and expired', () {
      expect(formatRemaining(30), '<1 min left');
      expect(formatRemaining(0), 'ending now');
      expect(formatRemaining(-5), 'ending now');
    });
    test('hours', () {
      expect(formatRemaining(3600), '1 h left');
      expect(formatRemaining(3600 + 5 * 60), '1 h 5 min left');
      expect(formatRemaining(4 * 3600), '4 h left');
    });
  });

  group('formatAsOf (staleness line — §1.4)', () {
    test('minutes', () {
      expect(formatAsOf(23 * 60), 'as of 23 min ago');
      expect(formatAsOf(16 * 60), 'as of 16 min ago');
    });
    test('hours and days', () {
      expect(formatAsOf(3 * 3600), 'as of 3 h ago');
      expect(formatAsOf(26 * 3600), 'as of 1 d ago');
    });
  });
}
