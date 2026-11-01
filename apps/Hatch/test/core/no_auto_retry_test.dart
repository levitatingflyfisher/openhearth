import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/engine/engine_providers.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/nursery/presentation/nursery_screen.dart';
import 'package:hatch/features/profiles/data/profiles_dao.dart';
import 'package:hatch/features/profiles/presentation/profile_picker_screen.dart';
import 'package:hatch/features/settings/data/settings_repository.dart';
import 'package:hatch/shared/audio/audio.dart';
import 'package:hatch/shared/theme/app_theme.dart';

/// A database whose engine snapshot read fails the way a broken disk does:
/// with an Exception (riverpod 3 retries Exceptions, not Errors).
class _BrokenSnapshotDb extends AppDatabase {
  _BrokenSnapshotDb() : super(NativeDatabase.memory());

  int snapshotReads = 0;

  @override
  SimpleSelectStatement<T, R> select<T extends HasResultSet, R>(
    ResultSetImplementation<T, R> table, {
    bool distinct = false,
  }) {
    if (table.entityName == 'engine_snapshots') {
      snapshotReads++;
      throw Exception('disk read failed');
    }
    return super.select(table, distinct: distinct);
  }
}

class _BrokenProfilesDao implements ProfilesDao {
  int reads = 0;

  @override
  Stream<List<Profile>> watchAll() {
    reads++;
    return Stream.error(Exception('disk read failed'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _BrokenSettingsRepository extends SettingsRepository {
  _BrokenSettingsRepository(super.db);

  int reads = 0;

  @override
  Stream<bool> watchSoundMuted() {
    reads++;
    return Stream.error(Exception('disk read failed'));
  }
}

class _SilentPlayer implements CuePlayer {
  @override
  Future<void> load(String assetPath) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}

/// A failed read of the device's own database is read once and stays failed.
/// Riverpod 3 would otherwise read it again up to 10 times on its own, from
/// 200 ms apart, and hold the screen on a blank loading state where the
/// error belongs. Hatch keeps riverpod 2's behaviour (no automatic retry) on
/// the providers themselves, so this holds in any scope, not only the root.
void main() {
  testWidgets('a failed engine load shows the refresh button and is read once',
      (tester) async {
    final db = _BrokenSnapshotDb();
    addTearDown(db.close);
    final audio = AudioService(
      isMuted: () => true,
      playerFactory: _SilentPlayer.new,
    );
    addTearDown(audio.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        audioServiceProvider.overrideWithValue(audio),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const NurseryScreen(profileId: 1),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    // Long enough for several of riverpod 3's default retries.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(db.snapshotReads, 1, reason: 'the disk is read once, not in a loop');
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget,
        reason: 'the refresh button stays, not a blank loading screen');

    // The button is how a household tries again, and it still works.
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    await tester.pump();
    expect(db.snapshotReads, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a failed profile list read shows its error and is read once',
      (tester) async {
    final dao = _BrokenProfilesDao();
    await tester.pumpWidget(ProviderScope(
      overrides: [profilesDaoProvider.overrideWithValue(dao)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProfilePickerScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    const message = 'Something went wrong opening the nest.';
    expect(find.text(message), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(dao.reads, 1, reason: 'the disk is read once, not in a loop');
    expect(find.text(message), findsOneWidget,
        reason: 'the error stays on screen, not a blank loading state');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a failed mute flag read is read once', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = _BrokenSettingsRepository(db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(soundMutedProvider, (_, _) {});
    addTearDown(sub.close);

    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(repo.reads, 1, reason: 'the disk is read once, not in a loop');
    expect(container.read(soundMutedProvider).hasError, isTrue);
  });
}
