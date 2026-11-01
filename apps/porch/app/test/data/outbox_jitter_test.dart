// W5: rotation fan-out jitter (BUILD-SPEC §1.6 / §3.6 step 3 / W5
// acceptance "Rotation fan-out applies 0–30 s jitter (unit-tested
// schedule)").
//
// The residual being mitigated: N near-simultaneous anonymous mailbox POSTs
// let a live-compromised relay infer probabilistic co-membership. Each
// sealed rotation bundle therefore gets an independent random delay in
// [0, 30] s before the outbox will deliver it. The delay is a HOLD, not a
// reorder of everything: entries that are not yet due are skipped silently
// (no attempt counted) while later due entries still deliver — safe because
// mailbox bundles are epoch-guarded and self-contained (see outbox.dart's
// retry-safety notes).
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/env.dart';
import 'package:porch_app/data/outbox.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
  });

  RosterEntry entryFor(TestDevice d, {required int joinedAt}) => RosterEntry(
        signPk: d.identity.sign.publicKey,
        boxPk: d.identity.box.publicKey,
        displayName: d.name,
        contactNote: '',
        joinedAt: joinedAt,
        isAdmin: false,
      );

  group('OutboxEntry.notBefore', () {
    test('round-trips through JSON and defaults to 0 for old state files',
        () {
      final entry = OutboxEntry(
        id: 'x',
        op: OutboxOp.mailbox,
        payload: {'mailboxId': 'm', 'blob': ''},
        createdAt: 100,
        notBefore: 130,
      );
      final decoded = OutboxEntry.fromJson(entry.toJson());
      expect(decoded.notBefore, 130);

      // A pre-jitter state file has no notBefore field — it must read as
      // "due immediately", never crash.
      final legacy = entry.toJson()..remove('notBefore');
      expect(OutboxEntry.fromJson(legacy).notBefore, 0);
    });
  });

  group('Outbox.drain hold semantics', () {
    test('a future-dated entry is held (no delivery, no attempt) and does '
        'not block later due entries', () async {
      final state = PorchState.initial();
      final now = world.clock.nowSec;
      final blob = Uint8List.fromList([1, 2, 3]);

      // Jittered rotation post, due in 30 s.
      Outbox.enqueue(state,
          op: OutboxOp.mailbox,
          payload: {'mailboxId': alice.identity.mailboxId, 'blob': b64(blob)},
          now: now,
          notBefore: now + 30);
      // An immediate bulletin enqueued AFTER it must still go out now —
      // jitter must never make the optimistic tap path wait.
      Outbox.enqueue(state,
          op: OutboxOp.bulletin,
          payload: {'channelId': 'c' * 43, 'blob': b64(blob)},
          now: now);

      final left = await Outbox.drain(state, world.relay, now: now);
      expect(left, 1, reason: 'held entry stays queued');
      expect(state.outbox.single.op, OutboxOp.mailbox);
      expect(state.outbox.single.attempts, 0,
          reason: 'holding is not a failed attempt');
      expect(world.relay.callLog, contains('bulletinPost'));
      expect(world.relay.callLog, isNot(contains('mailboxPost')));

      // Once due, it delivers.
      world.advance(30);
      final leftAfter =
          await Outbox.drain(state, world.relay, now: world.clock.nowSec);
      expect(leftAfter, 0);
      expect(world.relay.callLog, contains('mailboxPost'));
    });
  });

  group('rotation fan-out schedule', () {
    test('each sealed bundle gets its own injected jitter; nothing hits the '
        'mailboxes until its delay elapses', () async {
      // Alice with a scripted jitter sequence: Bob's removal fans out to
      // Carol (+5 s) and Dave (+30 s).
      final jitters = [5, 30];
      var i = 0;
      final jittered = await TestDevice.onboard(world,
          name: 'Alice2', seed: 7, rotationJitter: () => jitters[i++ % 2]);
      final bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
      final carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
      final dave = await TestDevice.onboard(world, name: 'Dave', seed: 4);

      final g = await jittered.groups.createGroup('My Porch');
      final st = await jittered.state();
      final sg = st.groupByUuid(g.groupUuid)!;
      sg.roster = Roster(members: [
        ...sg.roster.members,
        entryFor(bob, joinedAt: world.clock.nowSec + 1),
        entryFor(carol, joinedAt: world.clock.nowSec + 2),
        entryFor(dave, joinedAt: world.clock.nowSec + 3),
      ]);
      await jittered.store.save(st);

      final t0 = world.clock.nowSec;
      await jittered.groups
          .removeMember(g.groupUuid, memberPk: bob.identity.sign.publicKey);

      // Local adoption is immediate (the rotator never waits on network)...
      final after = (await jittered.state()).groupByUuid(g.groupUuid)!;
      expect(after.epoch, 2);
      // ...and the bulletin ops went out now (REMOVE + old-channel dup)...
      expect(world.relay.callLog.where((c) => c == 'bulletinPost').length, 2);
      // ...but NO mailbox post happened yet — both bundles are jittered.
      expect(world.relay.mailboxDepth(carol.identity.mailboxId), 0);
      expect(world.relay.mailboxDepth(dave.identity.mailboxId), 0);

      // The queued schedule is exactly now+5 / now+30, one per member.
      final held = (await jittered.state())
          .outbox
          .where((e) => e.op == OutboxOp.mailbox)
          .toList();
      expect(held.map((e) => e.notBefore).toSet(), {t0 + 5, t0 + 30});

      // +5 s: exactly one bundle out. +30 s: both.
      world.advance(5);
      await jittered.sync.refreshFeed();
      expect(
          world.relay.mailboxDepth(carol.identity.mailboxId) +
              world.relay.mailboxDepth(dave.identity.mailboxId),
          1);
      world.advance(25);
      await jittered.sync.refreshFeed();
      expect(world.relay.mailboxDepth(carol.identity.mailboxId), 1);
      expect(world.relay.mailboxDepth(dave.identity.mailboxId), 1);
    });

    test('production default (no injection) draws every delay from '
        '[0, 30] s', () async {
      // No rotationJitter injected → PorchEnv falls back to sodium
      // randombytes.uniform. Bounds are asserted, not exact values.
      final keys = await TestDevice.onboard(world, name: 'K', seed: 9);
      final env = PorchEnv(
        sodium: world.sodium,
        relay: world.relay,
        stateStore: keys.store,
        identity: keys.identity,
        now: () => world.clock.nowSec,
      );
      for (var n = 0; n < 200; n++) {
        final j = env.nextRotationJitterSec();
        expect(j, inInclusiveRange(0, rotationFanoutJitterMaxSec));
      }
    });
  });
}
