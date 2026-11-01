import 'package:bulwark/core/router/app_router.dart';
import 'package:bulwark/features/adoption/data/habit_state_repository.dart';
import 'package:bulwark/features/adoption/data/profile_repository.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';
import 'package:bulwark/features/adoption/domain/habit_state.dart';
import 'package:bulwark/features/adoption/domain/profile.dart';
import 'package:bulwark/features/home/presentation/home_screen.dart';
import 'package:bulwark/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/adoption_harness.dart';

/// Check-in opens over the sections, so Home is covered while the household
/// answers. Riverpod 3 pauses a hidden widget's watches. Check-in refreshes
/// the read models Home shows (here: whether today is still day one), and
/// Home must show the fresh value once Done brings it back.
void main() {
  testWidgets('Home shows a check-in made while Check-in covered it',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    final db = memoryDatabase();
    await tester.runAsync(() async {
      await ProfileRepository(db).save(const Profile(
        wakeMinutes: 7 * 60,
        bedMinutes: 22 * 60,
        goal: Goal.general,
        pace: Pace.moderate,
        onboarded: true,
      ));
      await HabitStateRepository(db).upsert(HabitState(
        interventionId: 'sleep-window',
        status: HabitStatus.active,
        activatedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      ));
    });

    // Drift answers on the real event loop; give it real time, then let the
    // fake clock run the fade transitions.
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [...adoptionOverrides(db: db), ...backupOverrides()],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ));
    await settle();

    final dayOne = find.textContaining('Your first day');
    expect(dayOne, findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Check in'));
    await settle();

    // Home is covered, so its tickers (and on riverpod 3 its watches) are
    // paused. This proves the test runs the paused case.
    final home = find.byType(HomeScreen, skipOffstage: false);
    expect(home, findsOneWidget);
    expect(TickerMode.of(tester.element(home)), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Did it').first);
    await settle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(dayOne, findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
