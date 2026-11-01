import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/router/app_shell.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/settings/domain/user_prefs.dart';

/// A milestone can be earned while another page covers the app shell: a stop
/// from the notification or an auto-stop while Export or Profiles is open.
/// AppShell hears it through ref.listen. Riverpod 3 pauses a hidden widget's
/// subscriptions; in flutter_riverpod 3.1.0 that is ref.watch only, and
/// ref.listen still fires, so today the line shows at once, as on riverpod 2.
/// This pins the outcome that matters whichever way a later riverpod goes:
/// the milestone line is there once the shell is visible again.
void main() {
  testWidgets('a milestone earned while the shell is covered still shows',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) => db),
      appModeProvider.overrideWith((_) => Stream.value(AppMode.rich)),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/timer',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/timer',
              builder: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        GoRoute(
          path: '/export',
          builder: (_, __) => const Scaffold(body: Text('covering page')),
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    router.push('/export');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('covering page'), findsOneWidget);
    // The shell's tickers are off while covered: this is the case riverpod 3
    // pauses (the shell's ref.watch subscriptions), so the test runs the
    // paused path and not only the visible one.
    final shell = tester.element(find.byType(AppShell, skipOffstage: false));
    expect(TickerMode.of(shell), isFalse);

    container.read(newlyEarnedBadgesProvider.notifier).show(const [
      Badge(id: 'b100', thresholdHours: 100, earnedAt: 1),
    ]);
    await tester.pump();

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('covering page'), findsNothing);
    expect(
      find.text('100h milestone: 100 hours outside, all time'),
      findsOneWidget,
      reason: 'the milestone must reach the household once the shell shows',
    );

    // Let the snackbar, the confetti and the 5 s clear run out.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
