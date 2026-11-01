/// Whole calendar days from [a] to [b], DST-safe. Both dates are reduced to
/// their **UTC midnight** before subtracting, so a daylight-saving transition
/// between them can never add or drop the hour that would skew a naive
/// `b.difference(a).inDays` (which truncates 167h to 6, not 7). Positive when
/// [b] is the later date; the calendar day is all that matters, times are
/// ignored.
int daysBetweenDates(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// [date]'s calendar day as a **UTC midnight**. In UTC every day is exactly
/// 24 hours, so `Duration`-stepping from this value always lands exactly one
/// calendar day away — unlike stepping a local DateTime, which drifts an
/// hour across a DST transition and can skip (or repeat) a wall-clock day.
/// Only the year/month/day fields are meaningful; format with a
/// field-reading formatter (e.g. `yyyy-MM-dd`), never convert back to local.
DateTime utcMidnight(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Every calendar day from [start] to [end], both included, each as a local
/// midnight. Steps by calendar day, not by 24 hours: across spring-forward
/// a 24-hour step lands an hour late on the next day, and the end day is
/// then missed.
List<DateTime> allDaysInRange(DateTime start, DateTime end) {
  final days = <DateTime>[];
  var d = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!d.isAfter(last)) {
    days.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

/// The local clock time that starts [date]'s calendar day and the one that
/// starts the next. The gap is 23 or 25 hours on a clock-change day, which
/// is why the end is a calendar step and not 24 hours on.
({DateTime start, DateTime end}) calendarDayBounds(DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  return (start: start, end: DateTime(date.year, date.month, date.day + 1));
}
