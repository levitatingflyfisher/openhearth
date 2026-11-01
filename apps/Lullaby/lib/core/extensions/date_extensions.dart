extension DateTimeExtensions on DateTime {
  String toRelativeTime() {
    final now = DateTime.now();
    final diff = now.difference(this);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  DateTime get startOfDay => DateTime(year, month, day);

  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  /// Local midnight [days] calendar days from this date (negative goes back).
  /// A `Duration(days: n)` step is 24-hour days, so across a clock change it
  /// lands an hour off, on the wrong side of midnight.
  DateTime startOfDayPlus(int days) => DateTime(year, month, day + days);
}
