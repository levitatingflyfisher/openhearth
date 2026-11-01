// W4 acceptance: groups — create, invite lifecycle (open → granted, void →
// regenerate), roster with admin ops (remove → rotation, transfer), and the
// sacred silent leave.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/domain/domain.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> openGroups(WidgetTester tester) async {
  await tapItem(tester, barAction('Groups'));
}

Future<void> openDetail(WidgetTester tester, String group) async {
  await openGroups(tester);
  await tapItem(tester, find.text(group));
}

void main() {

  testWidgets('create a group: pure client-side fact — appears instantly, '
      'relay hears nothing', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    final callsBefore = u.world.relay.callLog.length;

    await openGroups(tester);
    expect(find.text('My Porch'), findsOneWidget);

    await tapItem(tester, find.byType(FloatingActionButton));
    await tester.enterText(find.byType(TextField), 'Book club');
    await tapItem(tester, find.text('Create'));

    expect(find.text('Book club'), findsOneWidget);
    final state = (await u.store.load())!;
    expect(state.groups, hasLength(2));
    expect(u.world.relay.callLog.length, callsBefore,
        reason: 'no server call exists for group creation (§3.2)');
  });

  testWidgets('mint an invite: the link shows once, the row tracks it open; '
      'void → regenerate mints a genuinely fresh one', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openDetail(tester, 'My Porch');

    await tapItem(tester, find.text('Invite a friend'));
    expect(find.textContaining('porch://'), findsOneWidget);
    await tapItem(tester, find.text('Done'));

    expect(find.text('open'), findsOneWidget);
    var state = (await u.store.load())!;
    final firstId = state.groups.single.pendingInvites.single.inviteId;

    // Void it (one tap, §3.5 step 7)…
    await tapItem(tester, find.text('Void'));
    expect(find.text('void'), findsOneWidget);

    // …and regenerate: fresh invite, old one stays dead.
    await tapItem(tester, find.text('Regenerate'));
    expect(find.textContaining('porch://'), findsOneWidget);
    await tapItem(tester, find.text('Done'));

    state = (await u.store.load())!;
    final invites = state.groups.single.pendingInvites;
    expect(invites, hasLength(2));
    expect(invites.where((i) => i.status == InviteStatus.voided), hasLength(1));
    final fresh =
        invites.singleWhere((i) => i.status == InviteStatus.open);
    expect(fresh.inviteId, isNot(firstId));
  });

  testWidgets('invite lifecycle: a friend redeems, my refresh fulfills — '
      'row shows granted, roster shows the friend', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openDetail(tester, 'My Porch');
    await tapItem(tester, find.text('Invite a friend'));
    await tapItem(tester, find.text('Done'));

    // Bob redeems out-of-band (the link traveled by any channel).
    final state = (await u.store.load())!;
    final invite = state.groups.single.pendingInvites.single;
    final code = InviteToken(invite.t).toCode(u.world.sodium);
    final bob = await u.peer('Bob', seed: 2);
    final joined = await bob.invites.redeem(code);

    // Back home, refresh (the 25 s poll in real life).
    await tapItem(tester, find.byTooltip('Back'));
    await tapItem(tester, find.byTooltip('Back'));
    await refreshNow(tester);

    await openDetail(tester, 'My Porch');
    expect(find.text('granted'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    // And Bob can finish on his side.
    expect(await bob.invites.completeJoin(joined), isNotNull);
  });

  testWidgets('admin removes a member: confirm → gone from roster → key '
      'rotation happened (epoch advanced)', (tester) async {
    final u = await UiWorld.onboarded();
    await addFriend(u);
    await pumpPorch(tester, u);
    await openDetail(tester, 'My Porch');
    expect(find.text('Bob'), findsOneWidget);

    await tapItem(tester, find.byTooltip('Member actions: Bob'));
    await tapItem(tester, find.text('Remove from group'));
    // The confirm names the act and the person, and carries the urgency
    // icon: removal rotates the key at once, so it cannot be undone.
    expect(find.byIcon(Icons.report_outlined), findsOneWidget);
    await tapItem(tester, find.text('Remove Bob'));

    expect(find.text('Bob'), findsNothing);
    final state = (await u.store.load())!;
    expect(state.groups.single.roster.members, hasLength(1));
    expect(state.groups.single.epoch, 2,
        reason: 'REMOVE must rotate the group key (§3.6)');
  });

  testWidgets('transfer admin: the crown moves, no rotation', (tester) async {
    final u = await UiWorld.onboarded();
    final bob = await addFriend(u);
    await pumpPorch(tester, u);
    await openDetail(tester, 'My Porch');

    await tapItem(tester, find.byTooltip('Member actions: Bob'));
    await tapItem(tester, find.text('Make admin'));
    // Not destructive: no urgency icon, and the label names the act.
    expect(find.byIcon(Icons.report_outlined), findsNothing);
    await tapItem(tester, find.text('Make Bob admin'));

    final state = (await u.store.load())!;
    expect(
        state.groups.single.roster.isAdminPk(bob.identity.sign.publicKey),
        isTrue);
    expect(state.groups.single.epoch, 1, reason: 'no rotation on transfer');
  });

  testWidgets('silent leave: a confirm that promises silence, then the group '
      'is locally gone — and NOTHING notification-shaped exists anywhere',
      (tester) async {
    final u = await UiWorld.onboarded();
    await addFriend(u); // so someone remains
    await pumpPorch(tester, u);
    await openDetail(tester, 'My Porch');

    await tapItem(tester, find.text('Leave group'));
    expect(find.textContaining('No one is notified'), findsOneWidget);
    expect(find.byIcon(Icons.report_outlined), findsOneWidget);
    await tapItem(tester, find.text('Leave My Porch'));

    final state = (await u.store.load())!;
    expect(state.groups, isEmpty);
    expect(state.presence, isEmpty);
  });
}
