// W3-data: invite_repo — the §3.5 handshake wired to relay + storage:
// mint (register id + pinned escrow) → redeem → fulfill (fetch intro, JOIN
// op, sealed grant) → complete (take grant, verify, store group) — plus the
// terminal "void — regenerate" path.
import 'package:test/test.dart';

import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late TestDevice bob;
  late String uuid;

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
    uuid = (await alice.groups.createGroup('My Porch')).groupUuid;
  });

  test('mint registers ONLY the inviteId and pins a group-readable escrow',
      () async {
    final handle = await alice.invites.mint(uuid);
    expect(handle.link, startsWith('porch://i#'));
    expect(handle.code, contains('.'));

    final st = await alice.state();
    final pending = st.groupByUuid(uuid)!.pendingInvites.single;
    expect(pending.status, InviteStatus.open);
    expect(pending.inviteId, handle.inviteId);

    // The escrow rides the bulletin PINNED and decrypts to the same token.
    final g = st.groupByUuid(uuid)!;
    final channelId = deriveChannelId(world.sodium, g.keyring().current.gk);
    final entries = await world.relay.bulletinGet(channelId);
    final pinned = entries.where((e) => e.pinned).toList();
    expect(pinned, hasLength(1));
    final env = openEnvelope(world.sodium,
        wire: pinned.single.blob, keyring: g.keyring());
    final escrow = escrowFromEnvelope(world.sodium, env!);
    expect(escrow!.inviteId, handle.inviteId);
    expect(escrow.token.t, pending.t);

    // The relay accepted the registration: a join on that id works.
    await world.relay.joinInvite(inviteId: handle.inviteId, blob: pending.t);
  });

  test('FULL HANDSHAKE: mint → redeem → fulfill → complete; both derive the '
      'same channel', () async {
    final handle = await alice.invites.mint(uuid);

    // Bob (already onboarded, no server contact needed) pastes the code.
    final joined = await bob.invites.redeem(handle.code);
    expect(joined.inviteId, handle.inviteId);

    // Too early: no grant yet.
    expect(await bob.invites.completeJoin(joined), isNull);

    // Alice fulfills: intro decrypted, Bob folded in, grant posted.
    expect(await alice.invites.fulfillPending(uuid), 1);
    final aliceState = await alice.state();
    final aliceGroup = aliceState.groupByUuid(uuid)!;
    expect(aliceGroup.pendingInvites.single.status, InviteStatus.granted);
    final bobEntry =
        aliceGroup.roster.memberOf(bob.identity.sign.publicKey);
    expect(bobEntry, isNotNull);
    expect(bobEntry!.displayName, 'Bob');
    expect(bobEntry.isAdmin, isFalse);

    // Bob completes: group lands in his state with the same key material.
    final bobGroup = (await bob.invites.completeJoin(joined))!;
    expect(bobGroup.groupUuid, uuid);
    expect(bobGroup.name, 'My Porch');
    expect(bobGroup.epoch, aliceGroup.epoch);
    expect(
      deriveChannelId(world.sodium, bobGroup.keyring().current.gk),
      deriveChannelId(world.sodium, aliceGroup.keyring().current.gk),
    );
    expect(bobGroup.roster.isMember(alice.identity.sign.publicKey), isTrue);
    expect((await bob.state()).groupByUuid(uuid), isNotNull);

    // The grant is delete-after-retrieval: completing twice cannot replay.
    expect(await bob.invites.completeJoin(joined), isNull);
  });

  test('the JOIN announce rides the bulletin so other members fold Bob in',
      () async {
    final handle = await alice.invites.mint(uuid);
    await bob.invites.redeem(handle.code);
    await alice.invites.fulfillPending(uuid);

    final g = (await alice.state()).groupByUuid(uuid)!;
    final channelId = deriveChannelId(world.sodium, g.keyring().current.gk);
    final entries = await world.relay.bulletinGet(channelId);
    final types = [
      for (final e in entries)
        openEnvelope(world.sodium, wire: e.blob, keyring: g.keyring())?.type,
    ];
    expect(types, contains('JOIN'));
  });

  test('garbage code → ArgumentError; a consumed invite → RelayGone',
      () async {
    await expectLater(
        bob.invites.redeem('porch://i#not-a-real-code'),
        throwsA(isA<ArgumentError>()));
    final handle = await alice.invites.mint(uuid);
    await bob.invites.redeem(handle.code);
    final carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
    await expectLater(
        carol.invites.redeem(handle.code), throwsA(isA<RelayGone>()));
  });

  test('fulfillPending skips not-yet-joined invites and expired ones',
      () async {
    await alice.invites.mint(uuid); // nobody joined
    expect(await alice.invites.fulfillPending(uuid), 0);

    world.advance(73 * 3600); // past the 72 h TTL
    expect(await alice.invites.fulfillPending(uuid), 0);
  });

  test('VOID → REGENERATE mints a genuinely fresh, registered invite',
      () async {
    final old = await alice.invites.mint(uuid);
    final fresh = await alice.invites.regenerate(uuid, old.inviteId);
    expect(fresh.inviteId, isNot(old.inviteId));

    final st = await alice.state();
    final invites = st.groupByUuid(uuid)!.pendingInvites;
    expect(invites, hasLength(2));
    expect(invites.firstWhere((i) => i.inviteId == old.inviteId).status,
        InviteStatus.voided);
    expect(invites.firstWhere((i) => i.inviteId == fresh.inviteId).status,
        InviteStatus.open);

    // The fresh invite works end-to-end; the voided one is dead client-side.
    await bob.invites.redeem(fresh.code);
    expect(await alice.invites.fulfillPending(uuid), 1,
        reason: 'only the fresh invite is fulfillable');
  });

  test('mint requires the relay (typed error surfaces, nothing persisted)',
      () async {
    world.relay.offline = true;
    await expectLater(alice.invites.mint(uuid),
        throwsA(isA<RelayUnreachable>()));
    final st = await alice.state();
    expect(st.groupByUuid(uuid)!.pendingInvites, isEmpty,
        reason: 'no half-minted invite may linger');
  });

  test('a vandal join blob (undecryptable intro) voids the invite instead '
      'of granting', () async {
    final handle = await alice.invites.mint(uuid);
    // A vandal who saw only the inviteId posts garbage.
    await world.relay.joinInvite(
        inviteId: handle.inviteId,
        blob: (await alice.state()).groupByUuid(uuid)!.pendingInvites.single.t);
    expect(await alice.invites.fulfillPending(uuid), 0);
    final st = await alice.state();
    expect(st.groupByUuid(uuid)!.pendingInvites.single.status,
        InviteStatus.voided,
        reason: 'burned invite surfaces as "void — regenerate"');
  });
}
