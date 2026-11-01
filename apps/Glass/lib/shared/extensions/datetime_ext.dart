// Shared date helpers, kept in sync with the fleet copies of this file
// (fork-lineage siblings carry the same extension): change here, sync there —
// the DST-safety guarantees below must not diverge across apps.
import 'package:intl/intl.dart';

extension DateTimeExt on DateTime {
  static final _dayFmt = DateFormat('yyyy-MM-dd');
  static final _monthFmt = DateFormat('yyyy-MM');
  static final _yearFmt = DateFormat('yyyy');

  String toDateDay() => _dayFmt.format(this);
  String toYearMonth() => _monthFmt.format(this);
  String toYear() => _yearFmt.format(this);

  /// Midnight of this date, dropping the time component — the canonical form
  /// for the date-only keys the app's day-keyed tables store.
  DateTime get dateOnly => DateTime(year, month, day);

  /// The date-only Monday of this date's week (Dart weekday: Mon = 1 … Sun = 7),
  /// matching the weekly aggregation the app's date logic keys on.
  ///
  /// Calendar arithmetic (`DateTime(y, m, d - n)`), never Duration
  /// subtraction from local midnight: a DST transition between Monday
  /// midnight and this date's midnight makes a 24h-per-day walk land at
  /// 23:00 / 01:00 beside the Monday instead of exactly on it — the same
  /// class of bug [daysBetweenDates] below was rewritten to avoid.
  DateTime get startOfWeek => DateTime(year, month, day - (weekday - 1));
}

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

/// Parses a wall-clock string that carries no offset ("2026-03-08T02:00", as
/// Open-Meteo sends a place's local time) without involving the device's zone.
///
/// `DateTime.parse` would read it as a device-local time, and a wall time that
/// falls in the device zone's spring-forward gap is moved an hour on (02:00
/// becomes 03:00, so the hourly strip shows 3 AM twice). The result is flagged
/// UTC only so no zone can touch it: read `.hour`, `.day` and so on, never
/// `.toLocal()` or an instant comparison with a real clock reading.
DateTime parseWallTime(String s) {
  // Reading the fields out of a local parse is too late: the gap hour is
  // already gone. Naming the string UTC up front keeps the zone out of it.
  // Open-Meteo wall times never carry an offset, so "Z" is only appended to
  // those; a string that already has one is parsed as it stands.
  if (!s.contains('T')) return DateTime.parse('${s}T00:00:00Z');
  final hasOffset = RegExp(r'(Z|[+-]\d\d(:?\d\d)?)$').hasMatch(s);
  return DateTime.parse(hasOffset ? s : '${s}Z');
}

/// The same wall-clock fields as [t], zone-free (see [parseWallTime]), so a
/// wall time can be compared with another whichever way each was built.
DateTime asWallTime(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);

/// Minutes-since-midnight ⇄ display helper for time fields that persist as
/// `int` minutes.
String minutesToLabel(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = m.toString().padLeft(2, '0');
  return '$h12:$mm $period';
}
