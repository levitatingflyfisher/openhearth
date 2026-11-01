// A restore replaces every habit, mark and preference. The "Removed X" Undo
// and the awards waiting for their confetti live for the whole app, outside
// the database, so the restore hook must end them: otherwise tapping Undo
// writes pre-restore state into the restored field. These tests run the real
// hook, after a real restoreAll.

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/router/app_router.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/habits/data/focus_override_store.dart';
import 'package:furrow/features/habits/data/habit_marks_dao.dart';
import 'package:furrow/features/habits/data/habits_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/habits/domain/habit_enums.dart';
import 'package:furrow/features/sanctuary_backup/backup_config.dart';
import 'package:furrow/features/sanctuary_backup/data/backup_serializer.dart';

/// Hands the container's own Ref to the hook, the way the backup controller
/// calls it, outside any provider's build.
final _refProvider = Provider<Ref>((ref) => ref);

HabitsRepository _repo(AppDatabase db) =>
    HabitsRepository(HabitsDao(db), HabitMarksDao(db));

void main() {
  group('restore ends app-wide state that could write old data back', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)]);
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    /// What the backup controller does on a confirmed restore: replace the
    /// database, then run the app's hook.
    Future<void> restore(Uint8List backup) async {
      await FurrowBackupSerializer(db).restoreAll(backup);
      afterFurrowRestore(container.read(_refProvider));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test(
        'a pending "Removed" Undo is dropped, so it cannot bring back a '
        'habit the backup holds as removed', () async {
      final repo = _repo(db);
      final walk = await repo.createHabit(name: 'Walk', cadence: Cadence.binary);
      await repo.removeHabit(walk);
      // A backup taken now holds Walk as removed.
      final backup = await FurrowBackupSerializer(db).dumpAll();
      // The offer as the habit detail screen makes it on Remove.
      final undo = container.read(habitUndoProvider);
      var committed = false;
      undo.show(
        message: 'Removed Walk',
        onUndo: () => repo.restoreHabit(walk),
        onCommit: () async => committed = true,
      );

      await restore(backup);

      expect(undo.pending, isNull,
          reason: 'the Undo bar must not still offer the pre-restore removal');
      expect(committed, isFalse,
          reason: 'a restore never commits the old offer');
      await undo.undo();
      final removed = await repo.watchRemoved().first;
      expect(removed.map((h) => h.id), [walk],
          reason: 'the restored field holds Walk as removed and must keep it');
    });

    // The hook no longer invalidates the Drift streams by hand: the theme,
    // read from the userPrefs stream, must still follow the restore.
    test('the theme follows the restored preferences without an invalidate',
        () async {
      final sub = container.listen(themeModeProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(themeModeProvider), ThemeMode.system);
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.into(other.userPrefs).insert(
          UserPrefsCompanion.insert(key: 'theme', value: 'dark'));
      final backup = await FurrowBackupSerializer(other).dumpAll();

      await restore(backup);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('awards waiting for their confetti are cleared', () async {
      final badge = (await db.select(db.habitBadges).get()).first;
      container.read(newlyEarnedAwardsProvider.notifier).show([badge]);
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      final backup = await FurrowBackupSerializer(other).dumpAll();

      await restore(backup);

      expect(container.read(newlyEarnedAwardsProvider), isEmpty);
    });
  });

  // The audit flagged the week's focus virtue as possibly stale after a
  // restore. It is autoDispose and only Today watches it; Settings replaces
  // Today in the shell (context.go), so Today is gone while the restore runs
  // and the virtue is read again from the restored preferences on return.
  // This pins that, through the real router and the real screens.
  testWidgets(
      'Today shows the focus virtue the restored backup holds, not the old one',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // The backup: one virtue habit and this week's focus set to Order.
    final backup = await tester.runAsync(() async {
      final other = AppDatabase(NativeDatabase.memory());
      await _repo(other).createHabit(
          name: 'Walk', cadence: Cadence.binary, virtueKey: 'temperance');
      await FocusOverrideStore(other).setOverride(today, 'order');
      final bytes = await FurrowBackupSerializer(other).dumpAll();
      await other.close();
      return bytes;
    });
    // This device: the same kind of field, focused on Humility.
    await tester.runAsync(() async {
      await _repo(db).createHabit(
          name: 'Walk', cadence: Cadence.binary, virtueKey: 'temperance');
      await FocusOverrideStore(db).setOverride(today, 'humility');
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs!),
      secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
      cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
      sanctuaryAppDomainProvider.overrideWithValue('furrow'),
      sanctuaryBackupConfigProvider.overrideWithValue(furrowBackupConfig),
      backupSerializerProvider.overrideWithValue(FurrowBackupSerializer(db)),
    ]);

    Future<void> settle() async {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: container.read(appRouterProvider),
      ),
    ));
    await settle();
    expect(find.text('Humility'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await settle();
    await tester.runAsync(() => FurrowBackupSerializer(db).restoreAll(backup!));
    afterFurrowRestore(container.read(_refProvider));
    await settle();

    await tester.tap(find.text('Today'));
    await settle();
    expect(find.text('Order'), findsOneWidget);
    expect(find.text('Humility'), findsNothing);

    // Close the db first (it ends drift's stream timers), then the tree,
    // so no timer is pending at teardown; the order app_shell_test uses.
    await db.close();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
