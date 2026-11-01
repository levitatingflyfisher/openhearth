// Time formatting for the feed: the countdown ("time remaining", §3.4
// step 6) and the staleness line ("as of N min ago", §1.4).
//
// Both round in the HONEST direction: the countdown floors (never claim
// more time than remains) and the staleness line floors too (23.9 min old
// reads "23 min ago" — understating age is the one direction we refuse, so
// the threshold check itself lives on PresenceSnapshot.isStaleAt, not here).

/// Countdown from a presence entry's expiry. [secondsLeft] may be negative
/// (an entry the fold kept but the clock has since passed).
String formatRemaining(int secondsLeft) {
  if (secondsLeft <= 0) return 'ending now';
  if (secondsLeft < 60) return '<1 min left';
  final m = secondsLeft ~/ 60;
  if (m < 60) return '$m min left';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm == 0 ? '$h h left' : '$h h $rm min left';
}

/// The staleness line body. Callers gate on PresenceSnapshot.isStaleAt /
/// FeedModel.isStale — by the time this renders, the data IS old.
String formatAsOf(int ageSeconds) {
  final m = ageSeconds ~/ 60;
  if (m < 60) return 'as of $m min ago';
  final h = m ~/ 60;
  if (h < 24) return 'as of $h h ago';
  return 'as of ${h ~/ 24} d ago';
}
