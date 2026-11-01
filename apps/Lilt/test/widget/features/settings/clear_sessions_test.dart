import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/app/router.dart';
import 'package:lilt/features/results/solo_results_screen.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../../navigation/nav_harness.dart';

/// Fleet delete ruling: a deliberate delete does not ask; it deletes softly
/// and offers an Undo that never times out, and a lasting Recently cleared
/// list keeps the way back. Clear covers sessions in progress too, so a
/// couple abandoned half-way can always be cleared (item-09 concern 8).
void main() {
  late NavHarness h;
  setUp(() async => h = await NavHarness.create());
  tearDown(() async => h.dispose());

  Future<void> openSettings(WidgetTester tester) async {
    h.container.read(routerProvider).push('/settings');
    await NavHarness.settle(tester);
  }

  Future<void> tapClear(WidgetTester tester) async {
    final clear = find.text('Clear all sessions');
    await tester.scrollUntilVisible(clear, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(clear);
    await NavHarness.settle(tester);
  }

  Future<int> liveCount(WidgetTester tester) async =>
      (await tester.runAsync(() => h.sessions.getAllSessions()))!.length;

  testWidgets('Clear acts at once, clears in-progress too, and Undo stays',
      (tester) async {
    await tester.runAsync(() async {
      await h.rankedSession();
      await h.couple(bRanked: false, bComplete: false);
    });
    await h.pumpApp(tester);
    await openSettings(tester);

    await tapClear(tester);
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'a deliberate delete does not ask first');
    expect(await liveCount(tester), 0,
        reason: 'finished and in-progress sessions are both cleared');
    expect(find.text('Cleared 3 sessions'), findsOneWidget);

    // No timer: an hour later the offer is still there.
    await tester.pump(const Duration(hours: 1));
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await NavHarness.settle(tester);
    expect(await liveCount(tester), 3);
    expect(find.text('Cleared 3 sessions'), findsNothing);
  });

  testWidgets('Recently cleared outlives the screen: restore, delete forever',
      (tester) async {
    await tester.runAsync(() async {
      await h.rankedSession();
      await h.rankedSession();
    });
    await h.pumpApp(tester);
    await openSettings(tester);
    await tapClear(tester);

    // Leave Settings (the Undo lapses) and come back.
    h.container.read(routerProvider).pop();
    await NavHarness.settle(tester);
    await openSettings(tester);

    final heading = find.text('Recently cleared');
    await tester.scrollUntilVisible(heading, 200,
        scrollable: find.byType(Scrollable).first);
    expect(heading, findsOneWidget);

    final restore = find.text('Restore').first;
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await NavHarness.settle(tester);
    expect(await liveCount(tester), 1);

    final forever = find.text('Delete forever');
    await tester.ensureVisible(forever);
    await tester.tap(forever);
    await NavHarness.settle(tester);
    // Permanent, so it asks, and the button names the act.
    expect(find.text('Delete 1 session'), findsOneWidget);
    await tester.tap(find.text('Delete 1 session'));
    await NavHarness.settle(tester);

    expect(
        (await tester.runAsync(() => h.sessions.clearedSessions()))!, isEmpty);
    expect(await liveCount(tester), 1);
    expect(find.text('Recently cleared'), findsNothing);
  });

  testWidgets('Delete forever drops the cached results of what it deleted',
      (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = await h.rankedSession();
      // Results seen earlier stay cached: the provider is not autoDispose.
      await h.container.read(soloResultsProvider(id).future);
    });
    await h.pumpApp(tester);
    await openSettings(tester);
    await tapClear(tester);

    final forever = find.text('Delete forever');
    await tester.ensureVisible(forever);
    await tester.tap(forever);
    await NavHarness.settle(tester);
    await tester.tap(find.text('Delete 1 session'));
    await NavHarness.settle(tester);

    final error = await tester.runAsync(() async {
      try {
        await h.container.read(soloResultsProvider(id).future);
        return null;
      } on StateError catch (e) {
        return e;
      }
    });
    expect(error, isNotNull,
        reason: 'the deleted ranking must not stay in memory');
  });

  testWidgets('A restore on this screen ends the Undo and redraws '
      'Recently cleared', (tester) async {
    late Uint8List live, cleared;
    await tester.runAsync(() async {
      final a = await h.rankedSession();
      final b = await h.rankedSession();
      live = await h.backup();
      await h.sessions.clearAllSessions();
      cleared = await h.backup();
      await h.sessions.restoreSessions([a, b]);
    });
    await h.pumpApp(tester);
    await openSettings(tester);
    await tapClear(tester);
    expect(find.text('Undo'), findsOneWidget);

    // The backup holds both sessions live: nothing is cleared any more.
    await tester.runAsync(() => h.restore(live));
    await NavHarness.settle(tester);
    expect(find.text('Undo'), findsNothing,
        reason: 'the offer belongs to data the restore replaced');
    expect(find.text('Recently cleared'), findsNothing);

    // The backup holds both cleared: an old Undo would un-clear them.
    await tapClear(tester);
    await tester.runAsync(() => h.restore(cleared));
    await NavHarness.settle(tester);
    expect(find.text('Undo'), findsNothing);
    expect(await liveCount(tester), 0);
  });

  testWidgets('Clear with nothing to clear offers no Undo',
      (tester) async {
    await h.pumpApp(tester);
    await openSettings(tester);
    await tapClear(tester);
    expect(find.byType(OhUndoBar), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });
}
