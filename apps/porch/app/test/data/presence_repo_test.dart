// W3-data: presence_repo — the optimistic outbox-first tap path (§3.4
// step 1): local state flips and renders instantly; the encrypted event is
// queued and drained; the tap path NEVER blocks on network.
//
// Retry safety is protocol-level, not HTTP-level: a presence POST is a slot
// OVERWRITE (idempotent), so redelivery after an ambiguous failure cannot
// duplicate state. That is why presence retries live here and not in the
// HTTP client.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/outbox.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late String uuid;
  late String channelId;

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    final g = await alice.groups.createGroup('My Porch');
    uuid = g.groupUuid;
    channelId = deriveChannelId(world.sodium, g.keyring().current.gk);
  });

  test('OPTIMISTIC TAP: network down → local flip is instant, outbox queues',
      () async {
    world.relay.offline = true;
    final expiresAt = world.clock.nowSec + 3600;
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: expiresAt);

    final st = await alice.state();
    final snap = st.presence[uuid]!;
    final mine = snap.entries.single;
    expect(mine.memberSignPk, alice.identity.sign.publicKey);
    expect(mine.tag, '🚶');
    expect(mine.expiresAt, expiresAt);
    expect(st.outbox, hasLength(1), reason: 'queued for later');
    expect(world.relay.hasLivePresence(channelId), isFalse,
        reason: 'nothing reached the relay');
  });

  test('reconnect: drainOutbox delivers the queued slot write exactly once',
      () async {
    world.relay.offline = true;
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: world.clock.nowSec + 3600);
    world.relay.offline = false;

    expect(await alice.presence.drainOutbox(), 0);
    expect((await alice.state()).outbox, isEmpty);

    final slots = await world.relay.presenceGet(channelId);
    expect(slots, hasLength(1));
    // The blob decrypts and verifies as MY "on" event.
    final st = await alice.state();
    final env = openEnvelope(world.sodium,
        wire: slots.single.blob, keyring: st.groupByUuid(uuid)!.keyring());
    expect(env!.type, 'presence');
    expect(env.fields['status'], 'on');
    expect(env.senderSignPk, alice.identity.sign.publicKey);

    // A second drain is a no-op: nothing re-sends.
    final callsBefore = world.relay.callLog.length;
    expect(await alice.presence.drainOutbox(), 0);
    expect(world.relay.callLog.length, callsBefore);
  });

  test('online publish delivers inline and leaves an empty outbox', () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '💻', expiresAt: world.clock.nowSec + 1800);
    expect((await alice.state()).outbox, isEmpty);
    expect(world.relay.hasLivePresence(channelId), isTrue);
  });

  test('null groupUuids broadcasts to every defaultBroadcast group',
      () async {
    final g2 = await alice.groups.createGroup('Second');
    final st = await alice.state();
    st.groupByUuid(g2.groupUuid)!.defaultBroadcast = false;
    await alice.store.save(st);

    await alice.presence
        .publishAvailable(expiresAt: world.clock.nowSec + 600);
    expect(world.relay.hasLivePresence(channelId), isTrue);
    final ch2 = deriveChannelId(
        world.sodium,
        (await alice.state()).groupByUuid(g2.groupUuid)!.keyring().current.gk);
    expect(world.relay.hasLivePresence(ch2), isFalse,
        reason: 'defaultBroadcast=false groups are not in the default set');
  });

  test('publishOff posts a short tombstone and clears my local entry',
      () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: world.clock.nowSec + 3600);
    await alice.presence.publishOff(groupUuids: [uuid]);

    final st = await alice.state();
    expect(st.presence[uuid]!.entries, isEmpty, reason: 'local flip off');

    final slots = await world.relay.presenceGet(channelId);
    expect(slots, hasLength(1), reason: 'tombstone overwrote the slot');
    expect(slots.single.expiresAt, world.clock.nowSec + 60,
        reason: '60 s tombstone (§3.4 step 4)');
    final env = openEnvelope(world.sodium,
        wire: slots.single.blob, keyring: st.groupByUuid(uuid)!.keyring());
    expect(env!.fields['status'], 'off');
  });

  test('a queued publish whose expiry passed while offline is dropped, '
      'not sent', () async {
    world.relay.offline = true;
    await alice.presence.publishAvailable(
        groupUuids: [uuid], tag: '🚶', expiresAt: world.clock.nowSec + 100);
    world.advance(200); // expiry passes while offline
    world.relay.offline = false;
    expect(await alice.presence.drainOutbox(), 0);
    expect(world.relay.hasLivePresence(channelId), isFalse,
        reason: 'stale availability must never be resurrected');
  });

  test('permanently-rejected entries are dropped; transient failures keep '
      'order and stop the drain', () async {
    // Poison: a mailbox blob over the 8 KiB cap → 413 → dropped.
    final st = await alice.state();
    Outbox.enqueue(st,
        op: OutboxOp.mailbox,
        payload: {'mailboxId': 'm' * 43, 'blob': b64(Uint8List(9000))},
        now: world.clock.nowSec);
    Outbox.enqueue(st,
        op: OutboxOp.mailbox,
        payload: {'mailboxId': 'm' * 43, 'blob': b64(Uint8List(8))},
        now: world.clock.nowSec);
    await alice.store.save(st);

    expect(await alice.presence.drainOutbox(), 0,
        reason: 'poison dropped, good entry delivered');
    expect(world.relay.mailboxDepth('m' * 43), 1);

    // Transient: offline keeps the entry with attempts counted.
    world.relay.offline = true;
    await alice.presence.publishAvailable(
        groupUuids: [uuid], expiresAt: world.clock.nowSec + 600);
    expect(await alice.presence.drainOutbox(), 1);
    final after = await alice.state();
    expect(after.outbox.single.attempts, greaterThan(0));
  });

  test('publishing records on-device metrics (§5.2, never transmitted)',
      () async {
    await alice.presence.publishAvailable(
        groupUuids: [uuid], expiresAt: world.clock.nowSec + 600);
    world.advance(120);
    await alice.presence.publishAvailable(
        groupUuids: [uuid], expiresAt: world.clock.nowSec + 600);

    final metrics = (await alice.state()).metrics;
    expect(metrics, hasLength(1));
    expect(metrics.single.publishes, 2);
    expect(metrics.single.lastAt - metrics.single.firstAt, 120);
  });
}
