// W3-data: sync_service — RefreshFeed (§3.4 step 5) over the FakeRelay with
// real crypto end-to-end: bulletin fold by seq BEFORE presence decode,
// signed mailbox drain, rotation adoption before the next poll, snapshots
// that cannot exist without fetchedAt, widget mirroring, the wiped-store
// self-heal, and escrow fulfillment by the successor admin.
import 'package:test/test.dart';

import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late TestDevice bob;
  late String uuid;

  /// Onboards [d] into Alice's group through the REAL invite handshake.
  Future<void> join(TestDevice d) async {
    final handle = await alice.invites.mint(uuid);
    final joined = await d.invites.redeem(handle.code);
    await alice.invites.fulfillPending(uuid);
    expect(await d.invites.completeJoin(joined), isNotNull);
  }

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
    uuid = (await alice.groups.createGroup('My Porch')).groupUuid;
    await join(bob);
  });

  test('two devices see each other; fetchedAt is stamped on every snapshot',
      () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: world.clock.nowSec + 3600);
    await bob.presence.publishAvailable(
        groupUuids: [uuid], tag: '💻', expiresAt: world.clock.nowSec + 1800);

    world.advance(25);
    await bob.sync.refreshFeed();
    final bobSnap = (await bob.state()).presence[uuid]!;
    expect(bobSnap.fetchedAt, world.clock.nowSec);
    final aliceEntry = bobSnap.entries.singleWhere(
        (e) => bytesEqual(e.memberSignPk, alice.identity.sign.publicKey));
    expect(aliceEntry.tag, '🚶');

    await alice.sync.refreshFeed();
    final aliceSnap = (await alice.state()).presence[uuid]!;
    final bobEntry = aliceSnap.entries.singleWhere(
        (e) => bytesEqual(e.memberSignPk, bob.identity.sign.publicKey));
    expect(bobEntry.tag, '💻');
    expect(bobEntry.expiresAt, world.clock.nowSec - 25 + 1800);
  });

  test('ORDERING: roster ops fold before presence decode — a member who '
      'joined and published is visible in ONE refresh', () async {
    final carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
    await join(carol);
    await carol.presence.publishAvailable(
        groupUuids: [uuid], tag: '📖', expiresAt: world.clock.nowSec + 900);

    // Bob has never heard of Carol; one refresh must fold the JOIN (bulletin)
    // and THEN decode presence, or Carol's event would be dropped as foreign.
    world.relay.callLog.clear();
    await bob.sync.refreshFeed();
    final snap = (await bob.state()).presence[uuid]!;
    final carolEntry = snap.entries.singleWhere(
        (e) => bytesEqual(e.memberSignPk, carol.identity.sign.publicKey));
    expect(carolEntry.tag, '📖');

    final bulletinIdx = world.relay.callLog.indexOf('bulletinGet');
    final presenceIdx = world.relay.callLog.indexOf('presenceGet');
    expect(bulletinIdx, isNot(-1));
    expect(presenceIdx, greaterThan(bulletinIdx),
        reason: 'bulletin fold strictly precedes presence decode');
  });

  test('offline refresh keeps the LAST snapshot and its honest fetchedAt',
      () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], expiresAt: world.clock.nowSec + 3600);
    await bob.sync.refreshFeed();
    final before = (await bob.state()).presence[uuid]!;

    world.advance(1200);
    world.relay.offline = true;
    await bob.sync.refreshFeed(); // must not throw, must not lie
    final after = (await bob.state()).presence[uuid]!;
    expect(after.fetchedAt, before.fetchedAt,
        reason: 'no fetch happened, so fetchedAt must not move');
    expect(after.isStaleAt(world.clock.nowSec), isTrue,
        reason: '20 min old → the staleness line must render');
  });

  group('rotation via sync', () {
    late TestDevice carol;

    setUp(() async {
      carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
      await join(carol);
      await bob.sync.refreshFeed(); // bob folds carol's JOIN
    });

    test('LEAVE: admin rotates on fold; the other member adopts via mailbox; '
        'everyone converges; departed member is locked out', () async {
      final oldChannel = deriveChannelId(world.sodium,
          (await alice.state()).groupByUuid(uuid)!.keyring().current.gk);

      await bob.groups.leaveGroup(uuid); // silent LEAVE + local wipe

      await alice.sync.refreshFeed(); // folds LEAVE → alice is rotator
      final aliceGroup = (await alice.state()).groupByUuid(uuid)!;
      expect(aliceGroup.epoch, 2);
      expect(aliceGroup.roster.isMember(bob.identity.sign.publicKey), isFalse);

      await carol.sync.refreshFeed(); // folds LEAVE + adopts via mailbox
      final carolGroup = (await carol.state()).groupByUuid(uuid)!;
      expect(carolGroup.epoch, 2);
      expect(
        deriveChannelId(world.sodium, carolGroup.keyring().current.gk),
        deriveChannelId(world.sodium, aliceGroup.keyring().current.gk),
      );

      // New channel differs from old — bob lost key AND address.
      final newChannel =
          deriveChannelId(world.sodium, aliceGroup.keyring().current.gk);
      expect(newChannel, isNot(oldChannel));

      // Presence now flows on the NEW channel and still round-trips.
      await alice.presence.publishAvailable(
          groupUuids: [uuid], tag: '🧹', expiresAt: world.clock.nowSec + 600);
      expect(world.relay.hasLivePresence(newChannel), isTrue);
      await carol.sync.refreshFeed();
      final snap = (await carol.state()).presence[uuid]!;
      expect(
          snap.entries.any(
              (e) => bytesEqual(e.memberSignPk, alice.identity.sign.publicKey)),
          isTrue);

      // Idempotence: refreshing again never re-rotates.
      await alice.sync.refreshFeed();
      expect((await alice.state()).groupByUuid(uuid)!.epoch, 2);

      // Silence is structural: nothing notification-shaped exists to assert
      // on; the only artifacts of the leave are the roster and the epoch.
    });

    test('REMOVE: admin rotates immediately; peers adopt on refresh',
        () async {
      await alice.groups
          .removeMember(uuid, memberPk: bob.identity.sign.publicKey);
      expect((await alice.state()).groupByUuid(uuid)!.epoch, 2);

      await carol.sync.refreshFeed();
      final carolGroup = (await carol.state()).groupByUuid(uuid)!;
      expect(carolGroup.epoch, 2);
      expect(carolGroup.roster.isMember(bob.identity.sign.publicKey), isFalse);
    });

    test('grace window: a straggler still on the old epoch is rendered',
        () async {
      await bob.groups.leaveGroup(uuid);
      await alice.sync.refreshFeed(); // alice rotates to epoch 2

      // Carol hasn't refreshed — she publishes under epoch 1 on the OLD
      // channel. Alice must still see her (decrypt-last-2, poll old channel).
      await carol.presence.publishAvailable(
          groupUuids: [uuid], tag: '🚗', expiresAt: world.clock.nowSec + 900);
      await alice.sync.refreshFeed();
      final snap = (await alice.state()).presence[uuid]!;
      final carolEntry = snap.entries.singleWhere(
          (e) => bytesEqual(e.memberSignPk, carol.identity.sign.publicKey));
      expect(carolEntry.tag, '🚗');
    });

    test('WIPED-STORE SELF-HEAL: a straggler who lost the rotation regains '
        'the epoch via REKEY_REQUEST → re-grant', () async {
      await bob.groups.leaveGroup(uuid);
      await alice.sync.refreshFeed(); // rotation posted: mailbox + dup

      world.relay.wipeAll(); // total relay loss: carol's bundle is GONE

      await carol.sync.refreshFeed();
      expect((await carol.state()).groupByUuid(uuid)!.epoch, 1,
          reason: 'stuck on the old epoch — nothing arrived');

      await carol.sync.requestSelfHeal(uuid); // REKEY on the old channel
      await alice.sync.refreshFeed(); // sees request on grace channel, re-grants
      await carol.sync.refreshFeed(); // drains the re-grant, adopts

      final carolGroup = (await carol.state()).groupByUuid(uuid)!;
      expect(carolGroup.epoch, 2);
      expect(
        deriveChannelId(world.sodium, carolGroup.keyring().current.gk),
        deriveChannelId(
            world.sodium,
            (await alice.state()).groupByUuid(uuid)!.keyring().current.gk),
      );
    });

    test('ESCROW: the successor admin fulfills an orphaned invite', () async {
      final dave = await TestDevice.onboard(world, name: 'Dave', seed: 4);
      final handle = await alice.invites.mint(uuid);
      final joined = await dave.invites.redeem(handle.code);

      await alice.groups.leaveGroup(uuid); // inviter AND admin walks away

      // Bob folds the LEAVE; he is the oldest remaining member → admin and
      // rotator. His sync also ingests the pinned escrow.
      await bob.sync.refreshFeed();
      final bobGroup = (await bob.state()).groupByUuid(uuid)!;
      expect(bobGroup.roster.isAdminPk(bob.identity.sign.publicKey), isTrue);
      expect(bobGroup.epoch, 2);
      expect(bobGroup.pendingInvites.any((i) => i.inviteId == handle.inviteId),
          isTrue, reason: 'escrow ingested as a fulfillable invite');

      // Bob fulfills what Alice minted.
      expect(await bob.invites.fulfillPending(uuid), 1);
      final daveGroup = (await dave.invites.completeJoin(joined))!;
      expect(daveGroup.epoch, 2, reason: 'granted the CURRENT epoch');
      expect(
        deriveChannelId(world.sodium, daveGroup.keyring().current.gk),
        deriveChannelId(world.sodium,
            (await bob.state()).groupByUuid(uuid)!.keyring().current.gk),
      );
    });
  });

  test('widget mirror: refresh writes the §5.3 snapshot (friends only)',
      () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: world.clock.nowSec + 3600);
    await bob.presence.publishAvailable(
        groupUuids: [uuid], tag: '💻', expiresAt: world.clock.nowSec + 600);

    await bob.sync.refreshFeed();
    final written = bob.widgetMirror.writes.last;
    expect(written.availableCount, 1, reason: 'Alice only — self excluded');
    expect(written.top3.single.name, 'Alice');
    expect(written.top3.single.tag, '🚶');
    expect(written.fetchedAt, world.clock.nowSec);
  });
}
