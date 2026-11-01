import 'package:bulwark/features/notifications/next_instance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The first fire time of a daily reminder must be the chosen wall-clock time
/// even when a clock change falls between now and then. The location is
/// named, so this does not depend on the host's TZ.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('tomorrow 08:00 stays 08:00 when the clocks spring forward overnight',
      () {
    final ny = tz.getLocation('America/New_York');
    // Sat 7 Mar 2026, 09:00: today's 08:00 has passed. Clocks go forward at
    // 02:00 on Sun 8 Mar, so a plain +24h would land at 09:00 local.
    final now = tz.TZDateTime(ny, 2026, 3, 7, 9);
    final next = nextInstanceOfMinute(ny, now, 8 * 60);
    expect([next.year, next.month, next.day, next.hour, next.minute],
        [2026, 3, 8, 8, 0]);
  });

  test('tomorrow 08:00 stays 08:00 when the clocks fall back overnight', () {
    final ny = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(ny, 2026, 10, 31, 9);
    final next = nextInstanceOfMinute(ny, now, 8 * 60);
    expect([next.year, next.month, next.day, next.hour, next.minute],
        [2026, 11, 1, 8, 0]);
  });

  test('later today is today', () {
    final ny = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(ny, 2026, 3, 7, 6);
    final next = nextInstanceOfMinute(ny, now, 8 * 60);
    expect([next.day, next.hour], [7, 8]);
  });
}
