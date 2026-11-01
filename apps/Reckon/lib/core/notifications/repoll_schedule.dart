import 'dart:math';

import '../../shared/util/calendar_days.dart';
import 'notification_id.dart';

List<DateTime> computeRepollSchedule({
  required DateTime now,
  required DateTime? deadline,
  Random? random,
}) {
  if (deadline == null) return [];
  if (!deadline.isAfter(now)) return [];

  final rng = random ?? Random();
  final dates = <DateTime>[];
  DateTime cursor = now;

  while (dates.length < kMaxRepollSlots) {
    // Calendar arithmetic, not 24-hour Durations: across a clock change those
    // drop a day from the count and move the reminder an hour.
    final remaining = wholeDaysBetween(cursor, deadline);
    final int gap;
    if (remaining > 14) {
      gap = 5 + rng.nextInt(3);
    } else if (remaining > 7) {
      gap = 3;
    } else if (remaining > 3) {
      gap = 2;
    } else if (remaining > 0) {
      gap = 1;
    } else {
      break;
    }
    final next = addCalendarDays(cursor, gap);
    if (!next.isBefore(deadline)) break;
    dates.add(next);
    cursor = next;
  }

  return dates;
}
