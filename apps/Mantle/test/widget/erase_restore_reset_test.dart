// test/widget/erase_restore_reset_test.dart
//
// Settings is pushed over Home, so Home and what it watches stay alive while
// the household clears or restores data on Settings. These tests run the real
// Home, the real Settings and the real restore hook (mantleBackupConfig), and
// check that nothing on Home still shows data that is gone, and that the
// Clear all data Undo cannot bring an older safety copy back over a restore.

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/app/root_overrides.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:mantle/features/content/domain/domain.dart';
import 'package:mantle/features/home/presentation/home_screen.dart';
import 'package:mantle/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

const _words = 'abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon about';

const _continue = Key('home-continue-round');

void main() {
  late MantleDatabase db;
  late InMemoryVaultStore vault;

  setUp(() {
    db = MantleDatabase.forTesting(NativeDatabase.memory());
    vault = InMemoryVaultStore();
  });
  tearDown(() => db.close());

  List<Override> overrides({required bool backupSetUp}) => [
        databaseProvider.overrideWithValue(db),
        themePreferenceProvider
            .overrideWith((_) async => ThemePreference.light),
        secureKeyStoreProvider.overrideWithValue(backupSetUp
            ? InMemorySecureKeyStore(mnemonic: _words, acknowledged: true)
            : InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        vaultStoreProvider.overrideWithValue(vault),
        sanctuaryAppDomainProvider.overrideWithValue('mantle'),
        // The shipped config, so the shipped restore hook runs.
        sanctuaryBackupConfigProvider.overrideWithValue(mantleBackupConfig),
        backupSerializerProvider
            .overrideWith((ref) => MantleBackupSerializer(db)),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ];

  Future<void> addMember(String id, String label) => db.membersDao
      .add(id: id, label: label, color: 0xFF4CAF50, createdAt: DateTime(2026));

  /// A household round for Aria and Ben with one pick made: Home offers
  /// "Continue the round".
  Future<void> seedUnfinishedRound() async {
    await db.roundsDao
        .create(id: 'r1', deckVersion: 1, createdAt: DateTime(2026, 5));
    for (final m in ['m1', 'm2']) {
      for (final d in Domain.values) {
        await db.sessionsDao.create(
            id: 's-$m-${d.name}',
            roundId: 'r1',
            memberId: m,
            domain: d.name,
            createdAt: DateTime(2026, 5));
      }
    }
    await db.matchesDao.record(
        sessionId: 's-m1-architecture',
        idA: 'a',
        idB: 'b',
        outcome: 'aWins',
        decidedAt: DateTime(2026, 5));
  }

  Future<void> deleteRounds() async {
    await db.delete(db.rankingMatches).go();
    await db.delete(db.rankingSessions).go();
    await db.delete(db.rounds).go();
  }

  /// A backup of the data as it is now, made the way the app makes one.
  Future<Uint8List> backupNow() async {
    final c = ProviderContainer(overrides: overrides(backupSetUp: true));
    addTearDown(c.dispose);
    final snap =
        await c.read(backupControllerProvider.notifier).snapshotBeforeWipe();
    return (await c.read(backupVaultProvider).read(snap.entry!.id))!;
  }

  Future<void> openHome(WidgetTester tester, {bool backupSetUp = true}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(backupSetUp: backupSetUp),
      child: MaterialApp(theme: OhTheme.light(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-settings-button')));
    await tester.pumpAndSettle();
  }

  Future<void> tapClear(WidgetTester tester) async {
    await tester.scrollUntilVisible(
        find.byKey(const Key('settings-reset-button')), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-reset-button')));
    await tester.pumpAndSettle();
  }

  /// Restores [blob] the way Settings does: the package's controller, which
  /// runs the app's onAfterRestore when it is done.
  Future<void> restore(WidgetTester tester, Uint8List blob) async {
    final container =
        ProviderScope.containerOf(tester
        .element(find.byType(HomeScreen, skipOffstage: false)));
    final outcome = await container
        .read(backupControllerProvider.notifier)
        .restoreFromBlob(blob);
    expect(outcome, RestoreOutcome.success);
    await tester.pumpAndSettle();
  }

  group('Clear all data', () {
    setUp(() async {
      await addMember('m1', 'Aria');
      await addMember('m2', 'Ben');
      await seedUnfinishedRound();
    });

    testWidgets('with backup: Home no longer offers the cleared round',
        (tester) async {
      await openHome(tester);
      expect(find.byKey(_continue), findsOneWidget);

      await openSettings(tester);
      await tapClear(tester);
      expect(await db.select(db.rounds).get(), isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_continue), findsNothing,
          reason: 'the round it would continue is gone');
    });

    testWidgets('without backup: Home no longer offers the cleared round',
        (tester) async {
      await openHome(tester, backupSetUp: false);
      expect(find.byKey(_continue), findsOneWidget);

      await openSettings(tester);
      await tapClear(tester);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Clear all data')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_continue), findsNothing);
    });

    testWidgets('Undo brings the round back, and Home offers it again',
        (tester) async {
      await openHome(tester);
      await openSettings(tester);
      await tapClear(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_continue), findsOneWidget);
    });
  });

  group('Restore', () {
    setUp(() async {
      await addMember('m1', 'Aria');
      await addMember('m2', 'Ben');
    });

    testWidgets('Home no longer offers a round the backup does not hold',
        (tester) async {
      final noRound = await backupNow();
      await seedUnfinishedRound();

      await openHome(tester);
      expect(find.byKey(_continue), findsOneWidget);
      await openSettings(tester);
      await restore(tester, noRound);
      expect(await db.select(db.rounds).get(), isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_continue), findsNothing);
    });

    testWidgets('Home offers the unfinished round the backup holds',
        (tester) async {
      await seedUnfinishedRound();
      final withRound = await backupNow();
      await deleteRounds();

      await openHome(tester);
      expect(find.byKey(_continue), findsNothing);
      await openSettings(tester);
      await restore(tester, withRound);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_continue), findsOneWidget);
    });

    testWidgets('a pending Clear all data Undo is ended, so it cannot bring '
        'the older safety copy back over the restore', (tester) async {
      // The backup holds Ben only.
      await db.delete(db.members).go();
      await addMember('m2', 'Ben');
      final benOnly = await backupNow();
      await db.delete(db.members).go();
      await addMember('m1', 'Aria');

      await openHome(tester);
      await openSettings(tester);
      await tapClear(tester);
      expect(find.text('Undo'), findsOneWidget);

      await restore(tester, benOnly);
      expect(find.text('Undo'), findsNothing,
          reason: 'its safety copy (Aria) would replace the restored data');
      expect((await db.membersDao.all()).map((m) => m.label), ['Ben']);
    });
  });
}
