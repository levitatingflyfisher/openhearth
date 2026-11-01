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
import 'package:furrow/features/habits/presentation/log_time_sheet.dart';

/// The stopwatch added one second per timer tick, and a backgrounded app gets
/// no ticks, so time away from the screen was lost. It must measure from the
/// clock instead.
void main() {
  testWidgets('time passed while the app was not ticking is still counted',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = HabitsRepository(HabitsDao(db), HabitMarksDao(db));
    final id = await repo.createHabit(
        name: 'Read', cadence: Cadence.duration, targetValue: 1500);
    final habit = (await repo.getHabit(id))!;

    var now = DateTime(2026, 7, 13, 12);
    await withClock(Clock(() => now), () async {
      await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Scaffold(body: LogTimeSheet(habit: habit))),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Or run a timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();

      // Ten minutes go by with no timer ticks delivered (backgrounded).
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Pause'));
      await tester.pump();
      await tester.tap(find.text('Log it'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    final marks = await repo.allMarksOnce();
    expect(marks, hasLength(1));
    expect(marks.single.durationSecs, greaterThanOrEqualTo(600),
        reason: 'ten real minutes passed, not one counted tick');
  });
}
