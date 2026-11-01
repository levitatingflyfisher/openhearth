/// Whole calendar days from [from] to [to], safe across clock changes. Both
/// are reduced to their calendar day in UTC before subtracting, so a local
/// day that is 23 or 25 hours long can never drop or add a day, as
/// `to.difference(from).inDays` does (it truncates 191 hours to 7). The time
/// of day is ignored. Positive when [to] is the later day.
int daysBetweenDates(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// [date] moved by [days] calendar days (negative for earlier), keeping the
/// same wall-clock time. `date.add(Duration(days: n))` moves by n * 24 hours,
/// which lands an hour off, and sometimes on the wrong day, across a clock
/// change.
DateTime addCalendarDays(DateTime date, int days) => date.isUtc
    ? DateTime.utc(
        date.year,
        date.month,
        date.day + days,
        date.hour,
        date.minute,
        date.second,
        date.millisecond,
        date.microsecond,
      )
    : DateTime(
        date.year,
        date.month,
        date.day + days,
        date.hour,
        date.minute,
        date.second,
        date.millisecond,
        date.microsecond,
      );
