import 'package:clock/clock.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:still_life/services/notifications/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _FakeTZDateTime extends Fake implements tz.TZDateTime {}

class _FakeDetails extends Fake implements NotificationDetails {}

// The clocks go back on 1 November 2026 (United States). Stepping a reminder
// back by 7 * 24 hours from midnight on 5 November lands at 01:00 on
// 29 October, an hour off the day the owner asked for. Under TZ=UTC this
// passes before the fix; under TZ=America/New_York it does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  setUpAll(() {
    registerFallbackValue(_FakeTZDateTime());
    registerFallbackValue(_FakeDetails());
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
    registerFallbackValue(UILocalNotificationDateInterpretation.absoluteTime);
    registerFallbackValue(DateTimeComponents.dateAndTime);
  });

  test('a 7 day maintenance reminder lands at local midnight 7 days before', () async {
    final plugin = _MockPlugin();
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        uiLocalNotificationDateInterpretation: any(
          named: 'uiLocalNotificationDateInterpretation',
        ),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
      ),
    ).thenAnswer((_) async {});

    await withClock(Clock.fixed(DateTime(2026, 10, 1)), () {
      return NotificationService(plugin: plugin).scheduleMaintenanceReminder(
        logId: 'log-1',
        title: 'Boiler',
        dueDate: DateTime(2026, 11, 5),
        daysBefore: 7,
      );
    });

    final captured = verify(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        captureAny(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        uiLocalNotificationDateInterpretation: any(
          named: 'uiLocalNotificationDateInterpretation',
        ),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
      ),
    ).captured.single as tz.TZDateTime;
    expect(
      captured.millisecondsSinceEpoch,
      DateTime(2026, 10, 29).millisecondsSinceEpoch,
    );
  });
}
