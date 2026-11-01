import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/app/root_overrides.dart';
import 'package:lilt/app/stored_data_caches.dart';
import 'package:lilt/domain/models/ranking.dart';
import 'package:lilt/features/matchup/matchup_notifier.dart';
import 'package:lilt/features/name_detail/name_detail_screen.dart';
import 'package:lilt/features/results/couple_results_screen.dart';
import 'package:lilt/features/results/solo_results_screen.dart';
import 'package:lilt/features/settings/settings_screen.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/navigation/nav_harness.dart';

/// A restore replaces every session and comparison. The result screens read
/// through plain (not autoDispose) providers keyed by session id, so each
/// one keeps what it read until something invalidates it. These tests warm
/// every such cache on the old data, restore a backup, and check that each
/// one shows the backup, not the data the restore replaced.
void main() {
  late NavHarness h;
  late Uint8List backup;
  late String s, t, gone;

  const leader = 'alexander-n'; // The backup's top name in s and t.
  const climber = 'delphine-n'; // Top in s only after the backup was taken.

  setUp(() async {
    h = await NavHarness.create();
    // The backup: three finished sessions, earlier names beat later ones.
    s = await h.rankedSession();
    t = await h.rankedSession();
    final c = await h.rankedSession();
    backup = await h.backup();

    // Then the data moves on. Delphine climbs to the top of s, c is
    // cleared, and a session the backup does not hold is ranked.
    for (var round = 0; round < 3; round++) {
      for (final other in ['alexander-n', 'beatrice-n', 'cyrus-n']) {
        await h.sessions.recordMatch(
            sessionId: s,
            idA: climber,
            idB: other,
            outcome: ComparisonOutcome.aWins);
      }
    }
    await h.sessions.clearAllSessions();
    await h.sessions.restoreSessions([s, t]);
    expect((await h.sessions.clearedSessions()).single.id, c);
    gone = await h.rankedSession();
  });
  tearDown(() => h.dispose());

  ({String nameId, String? sessionAId, String? sessionBId}) detailOf(
          String sessionId) =>
      (nameId: climber, sessionAId: sessionId, sessionBId: null);

  test('Recently cleared shows the restored sessions, not the old list',
      () async {
    expect(await h.container.read(clearedSessionsProvider.future),
        hasLength(1));
    await h.restore(backup);
    expect(await h.container.read(clearedSessionsProvider.future), isEmpty,
        reason: 'the backup holds no cleared session');
  });

  test('solo results show the restored ranking', () async {
    final before = await h.container.read(soloResultsProvider(s).future);
    expect(before.ranked.first.id, climber);
    await h.restore(backup);
    final after = await h.container.read(soloResultsProvider(s).future);
    expect(after.ranked.first.id, leader);
  });

  test('couple results show the restored rankings', () async {
    final ids = (sessionAId: s, sessionBId: t);
    final before = await h.container.read(coupleResultsProvider(ids).future);
    expect(before.rankingsA.first.id, climber);
    await h.restore(backup);
    final after = await h.container.read(coupleResultsProvider(ids).future);
    expect(after.rankingsA.first.id, leader);
  });

  test('a name page shows the restored rank', () async {
    final before =
        await h.container.read(nameDetailProvider(detailOf(s)).future);
    expect(before.rankA, 1);
    await h.restore(backup);
    final after =
        await h.container.read(nameDetailProvider(detailOf(s)).future);
    final fresh = (await h.sessions.ranking(s)).rankOf(climber);
    expect(fresh, isNot(1));
    expect(after.rankA, fresh);
  });

  test('the matchup shows the restored comparisons, so a new one is '
      'scored against the backup', () async {
    final before = await h.container.read(matchupProvider(s).future);
    expect(before.matchCount, 15);
    await h.restore(backup);
    final after = await h.container.read(matchupProvider(s).future);
    expect(after.matchCount, 6, reason: 'four names, every pair once');
  });

  test('a session the backup does not hold no longer shows its results',
      () async {
    await h.container.read(soloResultsProvider(gone).future);
    await h.container.read(methodologyProvider(gone).future);
    await h.restore(backup);
    await expectLater(h.container.read(soloResultsProvider(gone).future),
        throwsA(isA<StateError>()));
    await expectLater(h.container.read(methodologyProvider(gone).future),
        throwsA(isA<StateError>()));
  });

  test('a pending Clear Undo is ended, so it cannot un-clear sessions in '
      'the restored data', () async {
    final sub = h.container.listen(clearSessionsUndoProvider, (_, _) {});
    addTearDown(sub.close);
    var undone = false;
    sub.read().show(
        message: 'Cleared 1 session', onUndo: () async => undone = true);
    await h.restore(backup);
    expect(sub.read().pending, isNull);
    await sub.read().undo();
    expect(undone, isFalse);
  });

  test('the shipped backup config runs afterLiltRestore', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: liltRootOverrides(prefs: prefs));
    addTearDown(c.dispose);
    expect(c.read(sanctuaryBackupConfigProvider).onAfterRestore,
        afterLiltRestore);
  });
}
