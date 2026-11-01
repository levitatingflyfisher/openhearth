/// [date] moved by [days] calendar days, keeping the clock time. Stepping a
/// local DateTime with `add(Duration(days: n))` moves it by n times 24 hours,
/// and across a clock change that lands an hour off, or on the wrong day.
DateTime addCalendarDays(DateTime date, int days) => date.isUtc
    ? DateTime.utc(date.year, date.month, date.day + days, date.hour,
        date.minute, date.second, date.millisecond, date.microsecond)
    : DateTime(date.year, date.month, date.day + days, date.hour, date.minute,
        date.second, date.millisecond, date.microsecond);

/// Whole days from [a] to [b] by the wall clock, floored. The two clock
/// readings are compared as if both were UTC, so a clock change between them
/// cannot take an hour off the gap and drop the count by one, which a plain
/// `b.difference(a).inDays` does on local dates.
int wholeDaysBetween(DateTime a, DateTime b) {
  DateTime asUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day, d.hour,
      d.minute, d.second, d.millisecond, d.microsecond);
  return asUtc(b).difference(asUtc(a)).inDays;
}
