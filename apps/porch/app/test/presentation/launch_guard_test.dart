// The start-up steps before the first screen (libsodium, the documents
// folder, the theme read) ran before runApp, so a failure there left a
// blank screen and no way to try again. LaunchGuard runs the whole
// start-up under a screen: a failure is shown with the fleet's error view
// and Try again, which runs start-up again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/presentation/launch_guard.dart';

void main() {
  testWidgets('a start-up that succeeds shows what it built', (tester) async {
    var starts = 0;
    await tester.pumpWidget(LaunchGuard(start: () async {
      starts++;
      return const Directionality(
          textDirection: TextDirection.ltr, child: Text('porch is up'));
    }));
    await tester.pumpAndSettle();

    expect(find.text('porch is up'), findsOneWidget);
    expect(starts, 1);
  });

  testWidgets('a start-up that fails is shown with Try again, never a '
      'blank screen; Try again runs it again', (tester) async {
    var starts = 0;
    var fail = true;
    await tester.pumpWidget(LaunchGuard(start: () async {
      starts++;
      if (fail) throw StateError('libsodium failed to load');
      return const Directionality(
          textDirection: TextDirection.ltr, child: Text('porch is up'));
    }));
    await tester.pumpAndSettle();

    expect(find.byType(OhErrorState), findsOneWidget);
    expect(find.textContaining('libsodium'), findsNothing,
        reason: 'the raw error stays behind Details');
    expect(starts, 1, reason: 'no retry loop');

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byType(OhErrorState), findsNothing);
    expect(find.text('porch is up'), findsOneWidget);
    expect(starts, 2);
  });
}
