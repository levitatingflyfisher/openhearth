import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/router/app_shell.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/habits/data/habit_marks_dao.dart';
import 'package:furrow/features/habits/data/habits_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/habits/domain/habit_enums.dart';
import 'package:furrow/features/habits/presentation/review_screen.dart';
import 'package:furrow/features/habits/presentation/today_screen.dart';

/// The evening review covers the whole shell (it is a route outside it, as
/// in the app router). A mark made there, and the award it earns, must both
/// be on the shell when the review closes. Riverpod 3 pauses a hidden
/// widget's ref.watch, so this test asserts that the shell really is hidden
/// (its tickers are off) while the mark is made.
void main() {
  testWidgets('a mark and award made in the review show on the shell after',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    final repo = HabitsRepository(HabitsDao(db), HabitMarksDao(db));
    final walkId = await repo.createHabit(name: 'Walk', cadence: Cadence.binary);

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        ShellRoute(
          builder: (_, _, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
          ],
        ),
        GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ));

    // Drift emits on a real timer; the confetti never settles, so pump.
    Future<void> settle() async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    double todayProgress() =>
        (tester.widget(find.byKey(ValueKey('today_$walkId'))) as dynamic)
            .progress as double;

    await settle();
    expect(todayProgress(), 0.0);

    router.push('/review');
    await settle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    final shellTickers = tester.widget<TickerMode>(find
        .ancestor(
          of: find.byType(AppShell, skipOffstage: false),
          matching: find.byType(TickerMode, skipOffstage: false),
        )
        .first);
    expect(shellTickers.enabled, isFalse,
        reason: 'the shell is hidden while the review covers it');

    await tester.tap(find.text('Done'));
    await settle();
    final marks = await tester.runAsync(() => repo.allMarksOnce());
    expect(marks!.single.completed, isTrue);

    router.pop();
    await settle();

    expect(find.byType(ReviewScreen), findsNothing);
    expect(todayProgress(), 1.0, reason: 'the mark shows on Today');
    expect(find.textContaining('First Light'), findsOneWidget,
        reason: 'the award earned in the review is named on the shell');

    // Drain the reveal's delayed clear, then close drift's stream timers.
    await tester.pump(const Duration(seconds: 6));
    await db.close();
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
