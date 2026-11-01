// W4: Riverpod wiring — session lifecycle, onboarding actions, and the
// refresh pipeline (sync → fulfill pending invites → notification diff).
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/presentation/providers.dart';

import 'support/ui_world.dart';

void main() {
  test('fresh install: no session, no state — onboarding territory',
      () async {
    final u = await UiWorld.fresh();
    final c = u.container();
    addTearDown(c.dispose);
    expect(await c.read(sessionProvider.future), isNull);
    expect(await c.read(porchStateProvider.future), isNull);
  });

  test('createIdentity is silent keygen: identity persists, session exists, '
      'and the relay heard NOTHING', () async {
    final u = await UiWorld.fresh();
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    await c.read(sessionProvider.notifier).createIdentity();
    final session = await c.read(sessionProvider.future);
    expect(session, isNotNull);
    expect(await u.keys.readEntropy(), isNotNull);
    expect(u.world.relay.callLog, isEmpty,
        reason: 'keygen must never touch the network');
  });

  test('completeOnboarding: profile name + auto-created "My Porch", self as '
      'admin — still zero relay calls (§3.2: groups are client-side facts)',
      () async {
    final u = await UiWorld.fresh();
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    await c.read(sessionProvider.notifier).createIdentity();
    await c.read(actionsProvider).completeOnboarding(displayName: 'Alice');

    final state = await c.read(porchStateProvider.future);
    expect(state!.profile.displayName, 'Alice');
    expect(state.groups.single.name, 'My Porch');
    final me = state.groups.single.roster.members.single;
    expect(me.displayName, 'Alice');
    expect(me.isAdmin, isTrue);
    expect(u.world.relay.callLog, isEmpty,
        reason: 'name and group must not leave the device at onboarding');
  });

  test('refresh pipeline: fulfills a redeemed invite, then a later refresh '
      'notifies (per-friend opt-in) when the new friend turns available',
      () async {
    final u = await UiWorld.onboarded();
    final c = u.container();
    addTearDown(c.dispose);
    final actions = c.read(actionsProvider);
    final state0 = await c.read(porchStateProvider.future);
    final groupUuid = state0!.groups.single.groupUuid;

    // Alice mints; Bob (another phone) redeems.
    final handle = await actions.mintInvite(groupUuid);
    final bob = await u.peer('Bob', seed: 2);
    final joined = await bob.invites.redeem(handle.code);

    // Alice's refresh must fulfill the pending invite (§3.5 step 4).
    u.advance(30);
    await actions.refresh();
    final afterFulfill = await c.read(porchStateProvider.future);
    expect(afterFulfill!.groups.single.roster.members, hasLength(2));
    expect(
        afterFulfill.groups.single.pendingInvites.single.status,
        InviteStatus.granted);

    // Bob completes, opts Alice into watching him, Bob turns available.
    final bobGroup = await bob.invites.completeJoin(joined);
    expect(bobGroup, isNotNull);
    await actions.setNotifyFriend(b64(bob.identity.sign.publicKey), true);
    u.advance(30);
    await bob.presence.publishAvailable(
        tag: 'walk', expiresAt: u.world.clock.nowSec + 3600);

    u.advance(30);
    await actions.refresh();
    final feedState = await c.read(porchStateProvider.future);
    expect(feedState!.presence[groupUuid]!.entries, isNotEmpty);
    expect(u.notifier.shown.single.$1, contains('Bob'));

    // Same feed, next refresh: nobody NEWLY available → silence.
    u.notifier.shown.clear();
    u.advance(30);
    await actions.refresh();
    expect(u.notifier.shown, isEmpty);
  });

  test('refresh while offline never throws and keeps the old snapshot',
      () async {
    final u = await UiWorld.onboarded();
    final c = u.container();
    addTearDown(c.dispose);
    final actions = c.read(actionsProvider);
    await actions.refresh(); // baseline snapshot
    final before = await c.read(porchStateProvider.future);
    final fetchedAt =
        before!.presence[before.groups.single.groupUuid]?.fetchedAt;

    u.world.relay.offline = true;
    u.advance(600);
    await actions.refresh(); // must not throw
    final after = await c.read(porchStateProvider.future);
    expect(after!.presence[after.groups.single.groupUuid]?.fetchedAt,
        fetchedAt, reason: 'offline refresh must keep the honest fetchedAt');
  });

  test('dismissFeedbackPrompt persists the 30-day dismissal', () async {
    final u = await UiWorld.onboarded();
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    await c.read(actionsProvider).dismissFeedbackPrompt();
    final state = await c.read(porchStateProvider.future);
    expect(state!.feedback.lastPromptAt, u.world.clock.nowSec);
  });
}
