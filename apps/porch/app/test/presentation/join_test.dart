// W4 acceptance: joining — paste the code (the primary tested path; the
// porch:// link parses identically), wait to be let in, complete.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> openJoin(WidgetTester tester) async {
  await tapItem(tester, barAction('Groups'));
  await tapItem(tester, find.text('Join with a code'));
}

void main() {

  testWidgets('paste code → join → waiting honestly → let in → the group '
      'appears with the roster delivered E2EE', (tester) async {
    final u = await UiWorld.onboarded(name: 'Bob', seed: 2);
    final carol = await u.peer('Carol', seed: 3);
    final g = await carol.groups.createGroup("Carol's porch");
    final handle = await carol.invites.mint(g.groupUuid);

    await pumpPorch(tester, u);
    await openJoin(tester);
    await tester.enterText(find.byType(TextField), handle.code);
    await tapItem(tester, find.text('Join'));

    // Honest waiting state: joining is a handshake, not an instant.
    expect(find.textContaining('Waiting'), findsOneWidget);

    // Carol (any member holding the token) lets Bob in.
    await carol.invites.fulfillPending(g.groupUuid);
    await tapItem(tester, find.text('Check now'));

    expect(find.text("Carol's porch"), findsOneWidget,
        reason: 'joined group appears in the groups list');
    final state = (await u.store.load())!;
    final joined =
        state.groups.singleWhere((x) => x.name == "Carol's porch");
    expect(joined.roster.members, hasLength(2));
  });

  testWidgets('an already-used invite tells the truth', (tester) async {
    final u = await UiWorld.onboarded(name: 'Bob', seed: 2);
    final carol = await u.peer('Carol', seed: 3);
    final g = await carol.groups.createGroup("Carol's porch");
    final handle = await carol.invites.mint(g.groupUuid);
    // Dave got there first.
    final dave = await u.peer('Dave', seed: 4);
    await dave.invites.redeem(handle.code);

    await pumpPorch(tester, u);
    await openJoin(tester);
    await tester.enterText(find.byType(TextField), handle.code);
    await tapItem(tester, find.text('Join'));

    expect(find.textContaining('already been used'), findsOneWidget);
  });

  testWidgets('garbage input gets a friendly rejection, not a crash',
      (tester) async {
    final u = await UiWorld.onboarded(name: 'Bob', seed: 2);
    await pumpPorch(tester, u);
    await openJoin(tester);
    await tester.enterText(find.byType(TextField), 'not-a-porch-code');
    await tapItem(tester, find.text('Join'));
    expect(find.textContaining("doesn’t look like a Porch invite"),
        findsOneWidget);
    // An error is colour, icon and word (fleet colour language), not red
    // text alone.
    expect(find.byKey(const Key('error-line-icon')), findsOneWidget);
  });
}
