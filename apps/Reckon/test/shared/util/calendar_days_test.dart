import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/shared/util/calendar_days.dart';

// These dates straddle the United States clock changes of 2026 (spring
// forward 8 March, fall back 1 November). In a zone with no clock change they
// pass trivially, so run them under TZ=America/New_York as well as UTC.
void main() {
  group('addCalendarDays', () {
    test('keeps the time of day across spring forward', () {
      final r = addCalendarDays(DateTime(2026, 3, 5, 9, 30), 6);
      expect(r, DateTime(2026, 3, 11, 9, 30));
    });

    test('keeps the time of day across fall back', () {
      final r = addCalendarDays(DateTime(2026, 10, 30, 9, 30), 5);
      expect(r, DateTime(2026, 11, 4, 9, 30));
    });

    test('lands on the next day when the clock jumps over midnight hour', () {
      final r = addCalendarDays(DateTime(2026, 3, 7, 23, 30), 1);
      expect(r.year, 2026);
      expect(r.month, 3);
      expect(r.day, 8);
    });
  });

  group('wholeDaysBetween', () {
    test('counts 15 days across spring forward as 15', () {
      expect(
        wholeDaysBetween(DateTime(2026, 3, 5, 9), DateTime(2026, 3, 20, 9)),
        15,
      );
    });

    test('counts 3 days across fall back as 3', () {
      expect(
        wholeDaysBetween(DateTime(2026, 10, 30, 9), DateTime(2026, 11, 2, 9)),
        3,
      );
    });

    test('still floors a part day', () {
      expect(
        wholeDaysBetween(DateTime(2026, 3, 5, 15), DateTime(2026, 3, 15, 9)),
        9,
      );
    });
  });
}
