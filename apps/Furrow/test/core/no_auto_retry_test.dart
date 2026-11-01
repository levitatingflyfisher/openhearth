import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/habits/data/awards_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/habits/presentation/garden_screen.dart';
import 'package:furrow/features/habits/presentation/today_screen.dart';
import 'package:furrow/features/settings/domain/settings_repository.dart';
import 'package:furrow/features/stats/presentation/stats_screen.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Every read fails the way a broken disk does: with an Exception. Riverpod 3
/// retries an Exception (never an Error) up to 10 times on its own; these
/// count how often the app asks.
class _BrokenRepo implements HabitsRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

class _BrokenAwards implements AwardsDao {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

class _BrokenSettings implements SettingsRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('disk read failed');
  }
}

/// Furrow keeps riverpod 2's behaviour: a provider that fails is not retried
/// on its own. Every failure here is a read of the phone's own database. A
/// loop against a broken disk helps nobody, and while it runs a spinner sits
/// where the plain error and its Try again belong. The household sees the
/// error and decides when to try again.
///
/// Each case runs in a plain ProviderScope, without the root scope's policy,
/// so this pins the policy each provider carries itself.
void main() {
  late AppDatabase db;
  late _BrokenRepo repo;
  late _BrokenAwards awards;
  late _BrokenSettings settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = _BrokenRepo();
    awards = _BrokenAwards();
    settings = _BrokenSettings();
  });
  tearDown(() => db.close());

  List<Override> overrides() => [
        appDatabaseProvider.overrideWithValue(db),
        habitsRepositoryProvider.overrideWithValue(repo),
        awardsDaoProvider.overrideWithValue(awards),
        settingsRepositoryProvider.overrideWithValue(settings),
      ];

  int allCalls() => repo.calls + awards.calls + settings.calls;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // Long enough for several of riverpod 3's default retries (200 ms, then
  // doubling).
  const wait = Duration(seconds: 5);

  final providers = <(String, AsyncValue<Object?> Function(WidgetRef))>[
    ('activeHabits', (ref) => ref.watch(activeHabitsProvider)),
    ('restingHabits', (ref) => ref.watch(restingHabitsProvider)),
    ('removedHabits', (ref) => ref.watch(removedHabitsProvider)),
    ('marksForDay', (ref) => ref.watch(marksForDayProvider('2026-11-12'))),
    ('marksForHabit', (ref) => ref.watch(marksForHabitProvider('h1'))),
    ('allMarks', (ref) => ref.watch(allMarksProvider)),
    ('awards', (ref) => ref.watch(awardsProvider)),
    ('userPrefs', (ref) => ref.watch(userPrefsProvider)),
    ('focusVirtue', (ref) => ref.watch(focusVirtueProvider('2026-11-12'))),
  ];

  for (final (name, watch) in providers) {
    testWidgets('$name: a failed read is asked once and stays an error',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: Consumer(builder: (context, ref, _) {
          final v = watch(ref);
          return Text(
            v is AsyncError ? 'error' : (v.isLoading ? 'loading' : 'data'),
            textDirection: TextDirection.ltr,
          );
        }),
      ));
      // focusVirtue reads the real (in-memory) database before the broken
      // repository, so give drift a real moment.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();
      final first = allCalls();
      expect(first, greaterThanOrEqualTo(1));
      expect(find.text('error'), findsOneWidget);

      await tester.pump(wait);
      await tester.pump();

      expect(allCalls(), first, reason: 'the disk is read once, not in a loop');
      expect(find.text('error'), findsOneWidget);
      await unmount(tester);
    });
  }

  for (final (name, screen) in [
    ('Today', const TodayScreen()),
    ('Garden', const GardenScreen()),
    ('Stats', const StatsScreen()),
  ]) {
    testWidgets('$name keeps its error and Try again, and reads once',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: Scaffold(body: screen)),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();
      final first = allCalls();
      expect(find.text('Try again'), findsOneWidget);

      await tester.pump(wait);
      await tester.pump();

      expect(allCalls(), first, reason: 'the disk is read once, not in a loop');
      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget,
          reason: 'the error and its way out stay on screen');
      await unmount(tester);
    });
  }
}
