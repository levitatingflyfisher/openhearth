// NOT a test (no _test suffix): a probe run as a child `dart` process under an
// explicit TZ by adherence_stats_dst_test.dart. The VM fixes its local zone at
// startup, so a specific clock-change week can only be pinned from outside.
import 'package:bulwark/features/adoption/domain/adherence_stats.dart';
import 'package:bulwark/features/adoption/domain/checkin.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';

void main() {
  // Run under TZ=America/Santiago: Saturday 2026-04-04 has 25 hours, inside
  // the week of Mon 2026-03-30.
  final keys = const AdherenceStats().weekly([
    Checkin(
        interventionId: 'a',
        date: DateTime(2026, 4, 5),
        result: CheckinResult.did),
  ]).keys;
  // ignore: avoid_print
  print('weekKey=${keys.single.toIso8601String()}');
}
