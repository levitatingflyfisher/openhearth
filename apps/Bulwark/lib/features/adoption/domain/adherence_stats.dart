import 'package:bulwark/features/adoption/domain/checkin.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';
import 'package:bulwark/shared/extensions/datetime_ext.dart';

/// One week's check-in tally. A `forgot` is a miss (it counts against the
/// did-rate) but is kept separate so the UI can nudge a better trigger.
class WeekAdherence {
  final int did;
  final int skipped;
  final int forgot;

  const WeekAdherence({this.did = 0, this.skipped = 0, this.forgot = 0});

  int get total => did + skipped + forgot;
  double get didRate => total == 0 ? 0 : did / total;
  double get forgotRate => total == 0 ? 0 : forgot / total;

  /// This tally with one more answer.
  WeekAdherence plus(CheckinResult r) => WeekAdherence(
        did: did + (r == CheckinResult.did ? 1 : 0),
        skipped: skipped + (r == CheckinResult.skipped ? 1 : 0),
        forgot: forgot + (r == CheckinResult.forgot ? 1 : 0),
      );
}

/// Weekly adherence aggregation. Deliberately weekly-only — Bulwark computes no
/// daily streak anywhere (missed days are data, not a broken chain). Weeks are
/// keyed by their date-only Monday.
class AdherenceStats {
  const AdherenceStats();

  /// Full per-week tallies keyed by the week's Monday.
  Map<DateTime, WeekAdherence> weekly(List<Checkin> checkins) {
    final byWeek = <DateTime, WeekAdherence>{};
    for (final c in checkins) {
      final week = c.date.startOfWeek;
      byWeek[week] = (byWeek[week] ?? const WeekAdherence()).plus(c.result);
    }
    return byWeek;
  }

  /// Weekly did-rate, keyed by the week's Monday.
  Map<DateTime, double> weeklyDidRate(List<Checkin> checkins) => {
        for (final e in weekly(checkins).entries) e.key: e.value.didRate,
      };
}
