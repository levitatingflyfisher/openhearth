import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The weekly tally is keyed by each week's Monday at local midnight. Walking
/// back from the check-in's midnight by whole 24h days lands an hour off when
/// a clock change sits inside the week, so the check-in is filed under a key
/// that is not a Monday midnight and the week splits in two.
void main() {
  test('a Sunday check-in in a 25-hour week is keyed to Monday midnight '
      '(child process, TZ=America/Santiago)', () async {
    final result = await Process.run(
      'dart',
      ['run', 'test/features/adoption/domain/adherence_week_key_probe.dart'],
      environment: {'TZ': 'America/Santiago'},
    );
    expect(result.exitCode, 0,
        reason: 'probe failed to run:\n${result.stdout}\n${result.stderr}');
    final match =
        RegExp('weekKey=(.*)').firstMatch(result.stdout as String);
    expect(match, isNotNull, reason: 'probe printed no result');
    expect(match!.group(1), '2026-03-30T00:00:00.000');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
