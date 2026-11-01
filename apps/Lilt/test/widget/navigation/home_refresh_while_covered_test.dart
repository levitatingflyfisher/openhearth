import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/app/router.dart';
import 'package:lilt/features/home/home_screen.dart';

import 'nav_harness.dart';

/// Matchup marks a session complete and refreshes Home's session list while
/// Home sits covered under it. Riverpod 3 pauses a hidden widget's
/// `ref.watch`, so the refresh waits until Home shows again. This pins that
/// the household still sees the finished session the moment they go back.
void main() {
  late NavHarness h;
  setUp(() async => h = await NavHarness.create());
  tearDown(() async => h.dispose());

  testWidgets('a session finished while Home is covered shows as Completed',
      (tester) async {
    final id = await tester
        .runAsync(() => h.rankedSession(label: 'Solo', complete: false))
        .then((v) => v!);
    await h.pumpApp(tester);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);

    final router = h.container.read(routerProvider);
    router.push('/matchup/$id');
    await NavHarness.settle(tester);

    // Home is covered: its tickers are off, which is when riverpod 3 pauses
    // its watch. This proves the test runs the paused case.
    final home = find.byType(HomeScreen, skipOffstage: false);
    expect(home, findsOneWidget);
    expect(TickerMode.of(tester.element(home)), isFalse);

    // What Matchup's finish does: mark complete, then refresh Home's list.
    await tester.runAsync(() => h.sessions.markComplete(id));
    h.container.invalidate(allSessionsProvider);
    await NavHarness.settle(tester);

    router.pop();
    await NavHarness.settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('In Progress'), findsNothing);
  });
}
