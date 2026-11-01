import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/habits/data/habit_marks_dao.dart';
import 'package:furrow/features/habits/data/habits_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/habits/domain/habit_enums.dart';
import 'package:furrow/features/habits/presentation/today_screen.dart';

/// The Today screen read the clock only when it built, so a phone left open
/// across midnight kept showing (and writing to) yesterday until something
/// else happened to rebuild it. It must roll over by itself, and when the app
/// comes back from the background.
void main() {
  late AppDatabase db;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Monday 2026-07-13, one minute before midnight.
    now = DateTime(2026, 7, 13, 23, 59);
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    await HabitsRepository(HabitsDao(db), HabitMarksDao(db))
        .createHabit(name: 'Walk', cadence: Cadence.binary);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: Scaffold(body: TodayScreen())),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  FontWeight? weightOf(WidgetTester tester, String letter) =>
      tester.widget<Text>(find.text(letter).first).style?.fontWeight;

  testWidgets('rolls to the new day when the app is resumed after midnight',
      (tester) async {
    await withClock(Clock(() => now), () async {
      await mount(tester);
      expect(weightOf(tester, 'Mo'), FontWeight.w800);

      now = DateTime(2026, 7, 14, 0, 1);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(weightOf(tester, 'Tu'), FontWeight.w800,
          reason: 'Tuesday is today after midnight');
      expect(weightOf(tester, 'Mo'), isNot(FontWeight.w800));
      await unmount(tester);
    });
  });

  testWidgets('rolls to the new day when left open across midnight',
      (tester) async {
    await withClock(Clock(() => now), () async {
      await mount(tester);
      expect(weightOf(tester, 'Mo'), FontWeight.w800);

      // Two minutes pass in the app's own time: the clock and the test's
      // fake time move together.
      now = DateTime(2026, 7, 14, 0, 1);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();

      expect(weightOf(tester, 'Tu'), FontWeight.w800);
      expect(weightOf(tester, 'Mo'), isNot(FontWeight.w800));
      await unmount(tester);
    });
  });
}
