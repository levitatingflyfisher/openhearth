// Start over, step one: leave every group, so the old identity is in no
// group. A backup file that leaks later then opens an identity nobody's
// group still holds. Each LEAVE goes to the relay at once (not left in the
// outbox), so the caller knows which groups heard it before anything is
// wiped; the other members' phones then change the group key.
import 'package:test/test.dart';

import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

void main() {
  late TestWorld world;
  late TestDevice alice;
  late TestDevice bob;
  late TestDevice carol;
  late String family;
  late String work;
  late String solo;

  Future<void> join(TestDevice host, TestDevice guest, String groupUuid) async {
    final handle = await host.invites.mint(groupUuid);
    final joined = await guest.invites.redeem(handle.code);
    await host.invites.fulfillPending(groupUuid);
    await guest.invites.completeJoin(joined);
  }

  Future<GroupKeyring> keyringOf(String groupUuid) async =>
      (await alice.state()).groupByUuid(groupUuid)!.keyring();

  Future<String> channelOf(String groupUuid) async =>
      deriveChannelId(world.sodium, (await keyringOf(groupUuid)).current.gk);

  setUp(() async {
    world = await TestWorld.create();
    alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);
    bob = await TestDevice.onboard(world, name: 'Bob', seed: 2);
    carol = await TestDevice.onboard(world, name: 'Carol', seed: 3);
    family = (await alice.groups.createGroup('Family')).groupUuid;
    work = (await alice.groups.createGroup('Work')).groupUuid;
    solo = (await alice.groups.createGroup('Just me')).groupUuid;
    await join(alice, bob, family);
    await join(alice, carol, work);
  });

  test('sends a LEAVE to every group with someone else in it, and forgets '
      'each group it reached', () async {
    final familyKeys = await keyringOf(family);
    final workKeys = await keyringOf(work);
    final familyChannel = await channelOf(family);
    final workChannel = await channelOf(work);

    final unreached = await alice.groups.leaveEveryGroup();

    expect(unreached, isEmpty);
    for (final (channel, keys) in [
      (familyChannel, familyKeys),
      (workChannel, workKeys),
    ]) {
      final last = (await world.relay.bulletinGet(channel)).last;
      final env =
          openEnvelope(world.sodium, wire: last.blob, keyring: keys);
      expect(env!.type, 'LEAVE');
      expect(env.senderSignPk, alice.identity.sign.publicKey);
    }
    final left = await alice.state();
    expect(left.groupByUuid(family), isNull);
    expect(left.groupByUuid(work), isNull);
    expect(left.groupByUuid(solo), isNotNull,
        reason: 'no one else is in it: there is no one to tell');
  });

  test('the member left behind changes the group key when it folds the '
      'LEAVE', () async {
    await alice.groups.leaveEveryGroup();
    await bob.sync.refreshFeed();
    final g = (await bob.state()).groupByUuid(family)!;
    expect(g.roster.isMember(alice.identity.sign.publicKey), isFalse);
    expect(g.epoch, 2, reason: 'the departure rotated the key');
  });

  test('a group the relay cannot reach is named and kept; the others are '
      'still left', () async {
    final familyKeys = await keyringOf(family);
    final familyChannel = await channelOf(family);
    world.relay.unreachableChannels.add(await channelOf(work));

    final unreached = await alice.groups.leaveEveryGroup();

    expect(unreached, ['Work']);
    final after = await alice.state();
    expect(after.groupByUuid(work), isNotNull,
        reason: 'not left: a later try can still tell it');
    expect(after.groupByUuid(family), isNull);
    final last = (await world.relay.bulletinGet(familyChannel)).last;
    expect(
        openEnvelope(world.sodium, wire: last.blob, keyring: familyKeys)?.type,
        'LEAVE');
  });

  test('an invite still open is burned first: its link no longer works',
      () async {
    final handle = await alice.invites.mint(family);
    await alice.groups.leaveEveryGroup();
    final dave = await TestDevice.onboard(world, name: 'Dave', seed: 4);
    expect(dave.invites.redeem(handle.code), throwsA(isA<RelayGone>()));
  });
}
