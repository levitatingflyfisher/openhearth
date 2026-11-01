import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/core/utils/date_arithmetic.dart';

// These dates straddle the 2026 United States clock changes (spring forward
// 8 March, fall back 1 November). Under TZ=UTC the naive code passes; under
// TZ=America/New_York a local day is 23 or 25 hours long and the naive code
// is a day out. Run the suite under both.
void main() {
  group('daysBetweenDates', () {
    test('counts whole calendar days across spring forward', () {
      expect(daysBetweenDates(DateTime(2026, 3, 7), DateTime(2026, 3, 15)), 8);
    });

    test('counts whole calendar days across fall back', () {
      expect(daysBetweenDates(DateTime(2026, 10, 30), DateTime(2026, 11, 5)), 6);
    });

    test('ignores the time of day', () {
      expect(
        daysBetweenDates(DateTime(2026, 3, 7, 23, 59), DateTime(2026, 3, 9, 0, 1)),
        2,
      );
    });

    test('is negative when the target is earlier', () {
      expect(daysBetweenDates(DateTime(2026, 3, 15), DateTime(2026, 3, 7)), -8);
    });
  });

  group('addCalendarDays', () {
    test('lands on the same wall-clock time across fall back', () {
      expect(
        addCalendarDays(DateTime(2026, 10, 30), 3),
        DateTime(2026, 11, 2),
      );
    });

    test('lands on the same wall-clock time across spring forward', () {
      expect(
        addCalendarDays(DateTime(2026, 3, 7, 9), 3),
        DateTime(2026, 3, 10, 9),
      );
    });

    test('steps backwards across fall back', () {
      expect(
        addCalendarDays(DateTime(2026, 11, 5), -7),
        DateTime(2026, 10, 29),
      );
    });
  });
}
