import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/habits/data/awards_dao.dart';
import 'package:furrow/features/habits/data/habit_marks_dao.dart';
import 'package:furrow/features/habits/data/habits_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/habits/domain/habit_enums.dart';
import 'package:furrow/features/habits/presentation/review_screen.dart';
import 'package:furrow/features/settings/presentation/settings_screen.dart';
import 'package:furrow/features/stats/presentation/stats_screen.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A failed read of the household's habits, marks or awards says so, with
// Try again. It is never drawn as every habit unmarked, as resting or
// removed habits gone, or as earned awards unearned. After Try again, with
// a read that works, the data is there.

final _disk = Exception('disk read failed');

class _Switch {
  bool marks = false;
  bool resting = false;
  bool removed = false;
  bool awards = false;
}

class _Habits extends HabitsRepository {
  _Habits(AppDatabase db, this.sw) : super(HabitsDao(db), HabitMarksDao(db));
  final _Switch sw;
  @override
  Stream<List<HabitMark>> watchMarksForDay(String dateDay) =>
      sw.marks ? Stream.error(_disk) : super.watchMarksForDay(dateDay);
  @override
  Stream<List<Habit>> watchArchived() =>
      sw.resting ? Stream.error(_disk) : super.watchArchived();
  @override
  Stream<List<Habit>> watchRemoved() =>
      sw.removed ? Stream.error(_disk) : super.watchRemoved();
}

class _Awards extends AwardsDao {
  _Awards(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<HabitBadge>> watchAll() =>
      sw.awards ? Stream.error(_disk) : super.watchAll();
}

void main() {
  late AppDatabase db;
  late _Switch sw;
  final pinned = DateTime(2026, 7, 24, 20);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sw = _Switch();
    final repo = HabitsRepository(HabitsDao(db), HabitMarksDao(db));
    await repo.createHabit(name: 'Morning pages', cadence: Cadence.binary);
    final resting =
        await repo.createHabit(name: 'Cold showers', cadence: Cadence.binary);
    await repo.setArchived(resting, true);
    final removed =
        await repo.createHabit(name: 'Night walks', cadence: Cadence.binary);
    await repo.removeHabit(removed);
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        habitsRepositoryProvider.overrideWithValue(_Habits(db, sw)),
        awardsDaoProvider.overrideWithValue(_Awards(db, sw)),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore(
          mnemonic: 'abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon abandon about',
          acknowledged: true,
          lastBackupAt: DateTime(2026, 7, 1),
        )),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('furrow'),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'furrow',
            aadContext: 'furrow-backup/v1',
            appDisplayName: 'Furrow',
          ),
        ),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
      ],
      child: MaterialApp(home: Scaffold(body: home)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  void expectSaid(WidgetTester tester, String title) {
    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  }

  Future<void> tryAgain(WidgetTester tester) async {
    sw
      ..marks = false
      ..resting = false
      ..removed = false
      ..awards = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsNothing);
  }

  testWidgets('Review: a failed read of the day’s marks is said, never '
      'every habit unmarked', (tester) async {
    sw.marks = true;
    await withClock(Clock.fixed(pinned), () async {
      await pump(tester, const ReviewScreen());

      expectSaid(tester, 'Couldn’t read this day’s marks');
      expect(find.text('Done'), findsNothing, reason: 'drawn as unmarked');
      expect(find.text('Yesterday'), findsOneWidget,
          reason: 'the day chips stay above the error');

      await tryAgain(tester);
      expect(find.text('Done'), findsOneWidget);
    });
    await unmount(tester);
  });

  testWidgets('Settings: a failed read of resting habits is said',
      (tester) async {
    sw.resting = true;
    await pump(tester, const SettingsScreen());

    expectSaid(tester, 'Couldn’t read your resting habits');

    await tryAgain(tester);
    expect(find.text('Cold showers'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Settings: a failed read of removed habits is said',
      (tester) async {
    sw.removed = true;
    await pump(tester, const SettingsScreen());

    expectSaid(tester, 'Couldn’t read your removed habits');

    await tryAgain(tester);
    expect(find.text('Night walks'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Stats: a failed read of awards is said, never unearned',
      (tester) async {
    sw.awards = true;
    await pump(tester, const StatsScreen());

    expectSaid(tester, 'Couldn’t read your awards');

    await tryAgain(tester);
    await unmount(tester);
  });
}
