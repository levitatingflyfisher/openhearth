// Every bulletin write names its writer by a bulletin writer id: derived
// from the channel's group key and the member, per epoch, and unlike the
// member's presence slot id, so the relay cannot tie a member's bulletins
// to their presence. The relay counts a channel as confirmed once two
// different writers have written there, so a quiet group that only ever
// writes bulletins keeps its place instead of spending a new opening on
// each write after 72 hours.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late TestDevice bob;
  late String groupUuid;

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
    final g = await alice.groups.createGroup('Family');
    groupUuid = g.groupUuid;
    final handle = await alice.invites.mint(groupUuid);
    final joined = await bob.invites.redeem(handle.code);
    await alice.invites.fulfillPending(groupUuid);
    await bob.invites.completeJoin(joined);
  });

  String slotOf(TestDevice d, Uint8List gk) =>
      deriveSlotId(world.sodium, gk, d.identity.sign.publicKey);

  String writerOf(TestDevice d, Uint8List gk) =>
      deriveBulletinWriterId(world.sodium, gk, d.identity.sign.publicKey);

  test('each bulletin write names its writer, and two writers confirm '
      'a channel that has seen no presence', () async {
    final gk = (await alice.state()).groupByUuid(groupUuid)!.keyring().current.gk;
    final channel = deriveChannelId(world.sodium, gk);

    await alice.groups.updateProfile(contactNote: 'Signal: @alice');
    await bob.groups.updateProfile(contactNote: 'Signal: @bob');

    final writers = world.relay.bulletinWriters[channel]!;
    expect(writers, isNot(contains(null)),
        reason: 'every bulletin write names its writer');
    expect(writers.toSet(), {writerOf(alice, gk), writerOf(bob, gk)});
    expect(writers, isNot(contains(slotOf(alice, gk))),
        reason: 'a bulletin never carries the presence slot id');
    expect(writers, isNot(contains(slotOf(bob, gk))));
    expect(world.relay.channelConfirmed(channel), isTrue);
  });

  test('a member keeps one writer id within an epoch and gets a new one '
      'when the epoch changes', () async {
    final oldGk =
        (await alice.state()).groupByUuid(groupUuid)!.keyring().current.gk;
    final oldChannel = deriveChannelId(world.sodium, oldGk);
    await alice.groups.updateProfile(contactNote: 'one');
    await alice.groups.updateProfile(contactNote: 'two');
    expect(world.relay.bulletinWriters[oldChannel]!.toSet(),
        {writerOf(alice, oldGk)});

    await alice.groups
        .removeMember(groupUuid, memberPk: bob.identity.sign.publicKey);
    final newGk =
        (await alice.state()).groupByUuid(groupUuid)!.keyring().current.gk;
    final newChannel = deriveChannelId(world.sodium, newGk);
    await alice.groups.updateProfile(contactNote: 'three');
    final newWriter = world.relay.bulletinWriters[newChannel]!.last;
    expect(newWriter, writerOf(alice, newGk));
    expect(newWriter, isNot(writerOf(alice, oldGk)));
  });

  test('a rotation copy on the old channel names the rotator by its '
      'old-epoch writer id', () async {
    final oldGk =
        (await alice.state()).groupByUuid(groupUuid)!.keyring().current.gk;
    final oldChannel = deriveChannelId(world.sodium, oldGk);

    await alice.groups
        .removeMember(groupUuid, memberPk: bob.identity.sign.publicKey);

    final writers = world.relay.bulletinWriters[oldChannel]!;
    expect(writers, isNot(contains(null)));
    expect(writers.last, writerOf(alice, oldGk));
  });

  test('a bulletin write queued offline keeps its writer for later',
      () async {
    final gk = (await alice.state()).groupByUuid(groupUuid)!.keyring().current.gk;
    final channel = deriveChannelId(world.sodium, gk);
    world.relay.offline = true;
    await alice.groups.updateProfile(contactNote: 'later');
    world.relay.offline = false;
    world.relay.bulletinWriters.clear();
    await alice.presence.drainOutbox();
    expect(world.relay.bulletinWriters[channel], [writerOf(alice, gk)]);
  });
}
