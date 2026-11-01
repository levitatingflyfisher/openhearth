import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/utils/date_arithmetic.dart';

/// Run under a DST zone to see the old defect:
/// `TZ=America/New_York flutter test test/utils/calendar_day_bounds_test.dart`.
void main() {
  group('calendarDayBounds', () {
    test('a day ends at the next local midnight when the clocks go back', () {
      // 1 November 2026 is 25 hours long in New York. Adding 24 hours to its
      // midnight ends the day at 23:00, so the gallery picker missed the
      // last hour of photos taken that evening.
      final b = calendarDayBounds(DateTime(2026, 11, 1, 15, 30));
      expect(b.start, DateTime(2026, 11, 1));
      expect(b.end, DateTime(2026, 11, 2));
    });

    test('a day ends at the next local midnight when the clocks go forward',
        () {
      // 8 March 2026 is 23 hours long: 24 hours on ends at 01:00 the next
      // day, and the picker showed an hour of the day after.
      final b = calendarDayBounds(DateTime(2026, 3, 8));
      expect(b.start, DateTime(2026, 3, 8));
      expect(b.end, DateTime(2026, 3, 9));
    });

    test('month and year ends roll over', () {
      expect(calendarDayBounds(DateTime(2026, 12, 31)).end, DateTime(2027, 1, 1));
    });
  });
}
