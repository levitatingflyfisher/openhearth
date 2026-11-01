// W3-data: group_repo — groups are client-side facts (§3.2: no server call
// exists for group creation). Membership ops seal as envelopes, ride the
// outbox, and fold optimistically into local state; removals rotate keys
// (§3.6) so the departed member loses decryption AND the channel address.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/relay_api.dart';
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

  group('createGroup', () {
    test('mints a purely client-side group: no relay call, self is admin',
        () async {
      final g = await alice.groups.createGroup('My Porch');
      expect(world.relay.callLog, isEmpty,
          reason: 'no server call exists for group creation');
      expect(g.name, 'My Porch');
      expect(g.epoch, 1);
      expect(g.keys.single.gk, hasLength(32));

      final persisted = (await alice.state()).groupByUuid(g.groupUuid)!;
      final me = persisted.roster.members.single;
      expect(me.signPk, alice.identity.sign.publicKey);
      expect(me.displayName, 'Alice');
      expect(me.isAdmin, isTrue);
      expect(persisted.roster.isAdminPk(alice.identity.sign.publicKey), isTrue);
    });

    test('two groups get distinct uuids and keys', () async {
      final a = await alice.groups.createGroup('A');
      final b = await alice.groups.createGroup('B');
      expect(a.groupUuid, isNot(b.groupUuid));
      expect(a.keys.single.gk, isNot(equals(b.keys.single.gk)));
    });
  });

  group('leaveGroup (silent — §3.6 step 1)', () {
    test('posts exactly one LEAVE envelope, wipes the group locally',
        () async {
      final g = await alice.groups.createGroup('My Porch');
      final oldKeyring = g.keyring();
      final channelId = deriveChannelId(world.sodium, oldKeyring.current.gk);

      await alice.groups.leaveGroup(g.groupUuid);

      expect((await alice.state()).groups, isEmpty, reason: 'keys wiped');
      expect((await alice.state()).presence, isEmpty);
      expect((await alice.state()).outbox, isEmpty, reason: 'drained');

      final entries = await world.relay.bulletinGet(channelId);
      expect(entries, hasLength(1), reason: 'one op, nothing else — silent');
      final env = openEnvelope(world.sodium,
          wire: entries.single.blob, keyring: oldKeyring);
      expect(env!.type, 'LEAVE');
      expect(env.senderSignPk, alice.identity.sign.publicKey);
    });

    test('offline leave still wipes locally; the LEAVE drains later',
        () async {
      final g = await alice.groups.createGroup('My Porch');
      final channelId =
          deriveChannelId(world.sodium, g.keyring().current.gk);
      world.relay.offline = true;
      await alice.groups.leaveGroup(g.groupUuid);
      expect((await alice.state()).groups, isEmpty);
      expect((await alice.state()).outbox, hasLength(1), reason: 'queued');

      world.relay.offline = false;
      await alice.presence.drainOutbox();
      expect(await world.relay.bulletinGet(channelId), hasLength(1));
      expect((await alice.state()).outbox, isEmpty);
    });
  });

  group('removeMember → rotation (§3.6)', () {
    test('admin removes: epoch advances, fan-out reaches remaining members '
        'only, dup rides the old channel', () async {
      final bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
      final carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);

      final g = await alice.groups.createGroup('My Porch');
      // Wire Bob and Carol straight into the roster (invite flow is
      // invite_repo's test; here we test rotation mechanics).
      final st = await alice.state();
      final sg = st.groupByUuid(g.groupUuid)!;
      sg.roster = Roster(members: [
        ...sg.roster.members,
        entryFor(bob, joinedAt: world.clock.nowSec + 1),
        entryFor(carol, joinedAt: world.clock.nowSec + 2),
      ]);
      await alice.store.save(st);

      final oldKeyring = sg.keyring();
      final oldChannel = deriveChannelId(world.sodium, oldKeyring.current.gk);

      await alice.groups
          .removeMember(g.groupUuid, memberPk: bob.identity.sign.publicKey);

      final after = (await alice.state()).groupByUuid(g.groupUuid)!;
      expect(after.epoch, 2, reason: 'departure rotates');
      expect(after.roster.isMember(bob.identity.sign.publicKey), isFalse);
      expect(after.roster.isMember(carol.identity.sign.publicKey), isTrue);
      expect(after.keys, hasLength(2), reason: 'grace epoch retained');

      // Carol got a sealed bundle; Bob got NOTHING.
      expect(world.relay.mailboxDepth(carol.identity.mailboxId), 1);
      expect(world.relay.mailboxDepth(bob.identity.mailboxId), 0);

      // Old channel: REMOVE op + ROTATION dup, in that order.
      final entries = await world.relay.bulletinGet(oldChannel);
      final types = [
        for (final e in entries)
          openEnvelope(world.sodium, wire: e.blob, keyring: oldKeyring)!.type,
      ];
      expect(types, ['REMOVE', 'ROTATION']);

      // Carol's sealed bundle opens and carries epoch 2 minus Bob.
      final sodium = world.sodium;
      final auth = buildDrainAuth(sodium,
          sign: carol.identity.sign,
          mailboxId: carol.identity.mailboxId,
          ts: world.clock.nowSec);
      final blobs = await world.relay
          .mailboxDrain(mailboxId: carol.identity.mailboxId, auth: auth);
      final bundle =
          openRotationBundle(sodium, myBox: carol.identity.box, sealed: blobs.single);
      expect(bundle!.epoch, 2);
      expect(bundle.roster.isMember(bob.identity.sign.publicKey), isFalse);
      expect(bundle.rotatorSignPk, alice.identity.sign.publicKey);

      // New channel differs — the departed member lost the ADDRESS too.
      final newChannel =
          deriveChannelId(sodium, after.keyring().current.gk);
      expect(newChannel, isNot(oldChannel));
    });

    test('non-admin cannot remove', () async {
      final bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
      final g = await alice.groups.createGroup('My Porch');
      final st = await alice.state();
      final sg = st.groupByUuid(g.groupUuid)!;
      // Demote self, promote bob (test-only surgery).
      sg.roster = Roster(members: [
        for (final m in sg.roster.members)
          m.copyWith(isAdmin: false),
        entryFor(bob, joinedAt: 1).copyWith(isAdmin: true),
      ]);
      await alice.store.save(st);
      await expectLater(
          alice.groups.removeMember(g.groupUuid,
              memberPk: bob.identity.sign.publicKey),
          throwsA(isA<StateError>()));
    });
  });

  group('transferAdmin / updateProfile', () {
    test('transferAdmin folds locally and posts the signed op', () async {
      final bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
      final g = await alice.groups.createGroup('My Porch');
      var st = await alice.state();
      st.groupByUuid(g.groupUuid)!.roster = Roster(members: [
        ...st.groupByUuid(g.groupUuid)!.roster.members,
        entryFor(bob, joinedAt: world.clock.nowSec),
      ]);
      await alice.store.save(st);

      await alice.groups
          .transferAdmin(g.groupUuid, toPk: bob.identity.sign.publicKey);
      st = await alice.state();
      final roster = st.groupByUuid(g.groupUuid)!.roster;
      expect(roster.isAdminPk(bob.identity.sign.publicKey), isTrue);
      expect(roster.isAdminPk(alice.identity.sign.publicKey), isFalse);

      final channelId = deriveChannelId(
          world.sodium, st.groupByUuid(g.groupUuid)!.keyring().current.gk);
      final entries = await world.relay.bulletinGet(channelId);
      final env = openEnvelope(world.sodium,
          wire: entries.single.blob,
          keyring: st.groupByUuid(g.groupUuid)!.keyring());
      expect(env!.type, 'TRANSFER_ADMIN');
    });

    test('updateProfile fans a PROFILE op to every group and updates state',
        () async {
      final a = await alice.groups.createGroup('A');
      final b = await alice.groups.createGroup('B');
      await alice.groups
          .updateProfile(displayName: 'Alice P.', contactNote: 'call me');

      final st = await alice.state();
      expect(st.profile.displayName, 'Alice P.');
      expect(st.profile.contactNote, 'call me');
      for (final uuid in [a.groupUuid, b.groupUuid]) {
        final sg = st.groupByUuid(uuid)!;
        expect(sg.roster.members.single.displayName, 'Alice P.');
        expect(sg.roster.members.single.contactNote, 'call me');
        final channelId =
            deriveChannelId(world.sodium, sg.keyring().current.gk);
        final entries = await world.relay.bulletinGet(channelId);
        final env = openEnvelope(world.sodium,
            wire: entries.single.blob, keyring: sg.keyring());
        expect(env!.type, 'PROFILE');
        expect(env.fields['displayName'], 'Alice P.');
      }
    });
  });

  group('rotateAfterDeparture reuse (sync path)', () {
    test('elected non-admin successor can rotate after the admin leaves',
        () async {
      // Alice's device, but the group's admin is Bob who just left; Alice
      // (oldest remaining) must be able to run the rotation herself.
      final bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
      final g = await alice.groups.createGroup('G');
      final st = await alice.state();
      final sg = st.groupByUuid(g.groupUuid)!;
      // Bob was admin and departed; Alice is the fold-promoted successor.
      sg.roster = Roster(members: [
        for (final m in sg.roster.members) m.copyWith(isAdmin: true),
      ]);
      await alice.store.save(st);

      await alice.groups.rotateAfterDeparture(g.groupUuid,
          departedPk: bob.identity.sign.publicKey);
      final after = (await alice.state()).groupByUuid(g.groupUuid)!;
      expect(after.epoch, 2);
    });
  });

  test('operations on an unknown group throw StateError', () async {
    await expectLater(
        alice.groups.leaveGroup('nope'), throwsA(isA<StateError>()));
    await expectLater(
        alice.groups.removeMember('nope', memberPk: Uint8List(32)),
        throwsA(isA<StateError>()));
  });
}
