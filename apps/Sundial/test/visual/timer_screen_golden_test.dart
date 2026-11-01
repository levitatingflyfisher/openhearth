import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/timer/presentation/timer_screen.dart';
import 'package:sundial/shared/theme/app_theme.dart';

import 'visual_golden_helper.dart';

/// Drain Drift-backed StreamBuilders before teardown (same pattern the unit
/// test in test/features/timer/timer_screen_test.dart uses).
Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

/// One idle sweep of the timer screen in [theme]; the dark sweep exists
/// because the app ships a dark theme and contrast faults hide there.
Future<void> _idleSweep(
    WidgetTester tester, String name, ThemeData theme) async {
  // TimerScreen's AppTextStyles now use BUNDLED font families (no google_fonts,
  // no network fetch at build time), so no font stub is needed.

  // Mirror makeTimerApp() from timer_screen_test.dart exactly: SharedPrefs
  // mock first, then the two core provider overrides. Rendered idle so the
  // SundialFace pulse AnimationController never repeats (pumpAndSettle would
  // otherwise hang on an infinite animation).
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // The year box now states pace, which depends on the date; pin it so
  // the golden does not change every day (1 January: nothing logged is
  // still "On pace").
  await withClock(
      Clock.fixed(DateTime(2026, 1, 1, 8)),
      () => goldenAtSizes(
            tester,
            name: name,
            theme: theme,
            home: ProviderScope(
              overrides: [
                appDatabaseProvider
                    .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: const TimerScreen(),
            ),
            sizes: const {
              'phone': Size(360, 800),
              'narrow': Size(320, 800),
            },
            textScales: const <double>[1.0, 3.0],
          ));

  await _tearDown(tester);
}

void main() {
  testWidgets('TimerScreen idle responsive golden sweep', (tester) async {
    await _idleSweep(tester, 'timer_screen', AppTheme.light);
  });

  testWidgets('TimerScreen idle golden sweep, dark theme', (tester) async {
    await _idleSweep(tester, 'timer_screen_dark', AppTheme.dark);
  });
}
