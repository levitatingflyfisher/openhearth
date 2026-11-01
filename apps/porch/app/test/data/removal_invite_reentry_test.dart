// SECURITY (§3.6 × §3.5): key rotation on member removal must also kill
// every OUTSTANDING invite for that group.
//
// The attack this file pins down: the invite token t is escrowed on the
// bulletin encrypted under the OLD group key (§3.5 step 2). A removed
// member still holds that key, so they can always DECRYPT the escrow and
// recover t — rotation cannot un-publish ciphertext. If the invite is
// still redeemable, they redeem it and any fulfiller mints them a grant
// carrying the NEW post-rotation key: rotation defeated. The fix must make
// the recovered token USELESS, not unreadable — the invite lands in the
// spec's terminal "void — regenerate" state (§3.5 step 7) and the relay
// join slot is burned so no device can be tricked into granting.
//
// Scope: REMOVE only. A benign LEAVE keeps outstanding invites alive by
// design — PRD gate 4's escrow rescue (successor admin fulfills the
// leaver's orphaned invite, sync_service_test) depends on it.
import 'package:test/test.dart';

import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late TestDevice mallory;
  late String uuid;

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    mallory = await TestDevice.onboard(world, name: 'Mallory', seed: 2);
    uuid = (await alice.groups.createGroup('My Porch')).groupUuid;
    // Mallory joins via the real §3.5 handshake, so her device genuinely
    // holds the pre-rotation group key — exactly what a removed member has.
    final handle = await alice.invites.mint(uuid);
    final joined = await mallory.invites.redeem(handle.code);
    expect(await alice.invites.fulfillPending(uuid), 1);
    expect(await mallory.invites.completeJoin(joined), isNotNull);
  });

  /// Mallory's post-removal move: read the OLD channel with the key she
  /// still holds and recover the escrowed token for [inviteId].
  Future<EscrowRecord?> recoverEscrow(
      GroupKeyring oldKeyring, String inviteId) async {
    final oldChannel =
        deriveChannelId(world.sodium, oldKeyring.current.gk);
    final entries = await world.relay.bulletinGet(oldChannel);
    for (final entry in entries) {
      final env = openEnvelope(world.sodium,
          wire: entry.blob, keyring: oldKeyring);
      if (env == null) continue;
      final escrow = escrowFromEnvelope(world.sodium, env);
      if (escrow != null && escrow.inviteId == inviteId) return escrow;
    }
    return null;
  }

  test(
      'REMOVAL VOIDS OUTSTANDING INVITES: an escrow-recovered token yields '
      'no post-rotation grant', () async {
    // An outstanding, unredeemed invite (meant for Bob) exists at removal
    // time — its token is escrowed under the CURRENT (soon old) key.
    final outstanding = await alice.invites.mint(uuid);
    final oldKeyring =
        (await mallory.state()).groupByUuid(uuid)!.keyring();

    await alice.groups
        .removeMember(uuid, memberPk: mallory.identity.sign.publicKey);
    final rotated = (await alice.state()).groupByUuid(uuid)!;
    expect(rotated.epoch, 2, reason: 'removal rotates');

    // The escrow ciphertext itself STAYS readable to old-key holders —
    // that is physics, not the bug. The fix makes the token useless.
    final recovered =
        await recoverEscrow(oldKeyring, outstanding.inviteId);
    expect(recovered, isNotNull,
        reason: 'removed member can always decrypt the old-key escrow');

    // 1. The recovered token no longer redeems: the one-time join slot is
    //    dead (burned at rotation), not sitting open for the attacker.
    await expectLater(
        mallory.invites.redeem(recovered!.token.toCode(world.sodium)),
        throwsA(isA<RelayError>()),
        reason: 'a removed member redeemed an escrowed invite '
            'AFTER rotation — re-entry');

    // 2. No fulfiller can mint a post-rotation grant from it.
    expect(await alice.invites.fulfillPending(uuid), 0,
        reason: 'the outstanding invite must not be fulfillable');
    final after = (await alice.state()).groupByUuid(uuid)!;
    expect(after.roster.isMember(mallory.identity.sign.publicKey), isFalse,
        reason: 're-granting would defeat the rotation entirely');

    // 3. The inviter sees the spec's terminal state: "void — regenerate".
    expect(
        after.pendingInvites
            .firstWhere((i) => i.inviteId == outstanding.inviteId)
            .status,
        InviteStatus.voided);
  });

  test(
      'ANOTHER MEMBER\'S DEVICE cannot be tricked either: an escrow copy '
      'ingested via sync voids when the REMOVE folds', () async {
    // Carol is a third member with her own device.
    final carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
    final carolHandle = await alice.invites.mint(uuid);
    final carolJoined = await carol.invites.redeem(carolHandle.code);
    expect(await alice.invites.fulfillPending(uuid), 1);
    expect(await carol.invites.completeJoin(carolJoined), isNotNull);

    // An outstanding invite exists; Carol's device ingests its escrow.
    final outstanding = await alice.invites.mint(uuid);
    await carol.sync.refreshFeed();
    final ingested = (await carol.state())
        .groupByUuid(uuid)!
        .pendingInvites
        .firstWhere((i) => i.inviteId == outstanding.inviteId);
    expect(ingested.status, InviteStatus.open,
        reason: 'escrow ingestion makes the invite fulfillable by Carol');

    // Mallory redeems BEFORE removal — the relay join slot now holds her
    // intro, so it cannot even be burned. Carol's device must still
    // refuse to grant once it learns of the rotation.
    final joinedByMallory =
        await mallory.invites.redeem(outstanding.code);

    await alice.groups
        .removeMember(uuid, memberPk: mallory.identity.sign.publicKey);

    // Carol syncs: folds the REMOVE (voiding her copy of every invite that
    // predates it) and adopts the rotation.
    await carol.sync.refreshFeed();
    final carolGroup = (await carol.state()).groupByUuid(uuid)!;
    expect(carolGroup.epoch, 2, reason: 'Carol adopted the rotation');
    expect(
        carolGroup.pendingInvites
            .firstWhere((i) => i.inviteId == outstanding.inviteId)
            .status,
        InviteStatus.voided,
        reason: 'folding a REMOVE must void outstanding invites on EVERY '
            'device, rotator or not');

    // Carol grants nothing; Mallory never receives the new key.
    expect(await carol.invites.fulfillPending(uuid), 0,
        reason: 'a not-yet-voided escrow copy would re-grant the removed '
            'member the post-rotation key');
    expect(await mallory.invites.completeJoin(joinedByMallory), isNull);
    expect(
        carolGroup.roster.isMember(mallory.identity.sign.publicKey), isFalse);
  });

  test('a FRESH invite minted after rotation still works end-to-end',
      () async {
    await alice.invites.mint(uuid); // outstanding at removal → voided
    await alice.groups
        .removeMember(uuid, memberPk: mallory.identity.sign.publicKey);

    final bob = await TestDevice.onboard(world, name: 'Bob', seed: 4);
    final fresh = await alice.invites.mint(uuid);
    final joined = await bob.invites.redeem(fresh.code);
    expect(await alice.invites.fulfillPending(uuid), 1,
        reason: 'only the fresh post-rotation invite is fulfillable');

    final bobGroup = (await bob.invites.completeJoin(joined))!;
    final aliceGroup = (await alice.state()).groupByUuid(uuid)!;
    expect(bobGroup.epoch, aliceGroup.epoch);
    expect(
      deriveChannelId(world.sodium, bobGroup.keyring().current.gk),
      deriveChannelId(world.sodium, aliceGroup.keyring().current.gk),
      reason: 'Bob lands on the post-rotation channel',
    );
    expect(bobGroup.roster.isMember(mallory.identity.sign.publicKey),
        isFalse);
  });
}
