import 'package:timezone/timezone.dart' as tz;

/// The next wall-clock occurrence of [minutesSinceMidnight] in [location] after
/// [now]: today if it is still ahead, tomorrow otherwise.
tz.TZDateTime nextInstanceOfMinute(
  tz.Location location,
  tz.TZDateTime now,
  int minutesSinceMidnight,
) {
  tz.TZDateTime at(int dayOffset) => tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + dayOffset,
        minutesSinceMidnight ~/ 60,
        minutesSinceMidnight % 60,
      );
  // Build tomorrow from the calendar date: adding 24h lands an hour off when
  // the clocks change overnight.
  final today = at(0);
  return today.isAfter(now) ? today : at(1);
}
