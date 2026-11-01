import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/utils/date_arithmetic.dart';

/// Run under a DST zone to see the old defect:
/// `TZ=America/New_York flutter test test/utils/days_in_range_test.dart`.
void main() {
  group('allDaysInRange', () {
    test('includes the last day across spring-forward', () {
      // Old code stepped local midnights by 24h: Mar 8 + 24h = Mar 9 01:00,
      // so every later step sat an hour late and the end day was dropped.
      final days = allDaysInRange(DateTime(2026, 3, 7), DateTime(2026, 3, 10));
      expect(days, [
        DateTime(2026, 3, 7),
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 10),
      ]);
    });

    test('every day is a local midnight', () {
      final days = allDaysInRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      expect(days.length, 31);
      expect(days.every((d) => d.hour == 0 && d.minute == 0), isTrue);
    });

    test('one day range is that day, and a reversed range is empty', () {
      expect(allDaysInRange(DateTime(2026, 3, 8), DateTime(2026, 3, 8)),
          [DateTime(2026, 3, 8)]);
      expect(allDaysInRange(DateTime(2026, 3, 9), DateTime(2026, 3, 8)),
          isEmpty);
    });
  });
}
