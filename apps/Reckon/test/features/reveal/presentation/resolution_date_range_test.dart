import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/features/reveal/presentation/resolution_date_screen.dart';

// 7 March 2026 23:30 is the evening before the United States spring-forward
// day. Run under TZ=America/New_York as well as UTC.
void main() {
  test('the earliest check-in date is tomorrow, even before a clock change',
      () {
    final r = resolutionPickerRange(DateTime(2026, 3, 7, 23, 30));
    expect((r.first.year, r.first.month, r.first.day), (2026, 3, 8));
  });

  test('the suggested date is 30 calendar days out', () {
    final r = resolutionPickerRange(DateTime(2026, 3, 7, 23, 30));
    expect((r.initial.year, r.initial.month, r.initial.day), (2026, 4, 6));
  });

  test('the last date is 1825 calendar days out', () {
    final r = resolutionPickerRange(DateTime(2026, 3, 7, 23, 30));
    expect((r.last.year, r.last.month, r.last.day), (2031, 3, 6));
  });
}
