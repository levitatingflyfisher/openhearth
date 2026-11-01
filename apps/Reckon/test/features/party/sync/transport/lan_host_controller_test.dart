import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/database/app_database.dart';
import 'package:reckon/features/party/data/group_repository_impl.dart';
import 'package:reckon/features/party/data/local_party_repository.dart';
import 'package:reckon/features/party/domain/entities/ballot.dart';
import 'package:reckon/features/party/domain/entities/party.dart';
import 'package:reckon/features/party/domain/entities/party_result.dart';
import 'package:reckon/features/party/sync/party_codec.dart';
import 'package:reckon/features/party/sync/party_crypto.dart';
import 'package:reckon/features/party/sync/party_key_store.dart';
import 'package:reckon/features/party/sync/party_link.dart';
import 'package:reckon/features/party/sync/transport/channel_relay.dart';
import 'package:reckon/features/party/sync/transport/lan_host_controller.dart';
import 'package:reckon/features/party/sync/transport/lan_socket_channel.dart';

/// The host controller, end-to-end over real loopback TCP: it hosts a party,
/// a remote peer votes over the socket, and `syncToLocal` folds that vote into
/// the host's own tally.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('hosts a party, then merges a peer vote into the local tally', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPartyRepository(db);
    final keys = InMemoryPartyKeyStore();

    final party = await repo.createParty(
      title: 'Where to?',
      options: const [
        PartyOption(id: 'a', label: 'Park'),
        PartyOption(id: 'b', label: 'Pub'),
      ],
      votingMethod: VotingMethod.approval,
    );
    // The host has already cast its own vote locally.
    await repo.submitBallot(
        party.id,
        Ballot.approval(
            id: 'host', party: party, approvedOptionIds: const ['a']));

    final controller = LanHostController(repo, keys, GroupRepositoryImpl(db));
    addTearDown(controller.stop);
    final hosted = await controller.start(party.id);

    // The link is a lan:// link carrying the key the controller persisted.
    final link = PartyJoinLink.parse(hosted.joinLink)!;
    expect(link.relayBaseUrl, 'lan://${hosted.address}:${hosted.port}');
    final key = (await keys.get(party.id))!.keyString;

    // A peer connects over loopback, fetches + decrypts, and votes.
    final channel = await connectToLanHost('127.0.0.1', hosted.port);
    final peer = ChannelPartyRelay(channel);
    addTearDown(peer.dispose);
    final crypto = PartyCrypto.fromKeyString(key);

    final snap = (await peer.fetchParty(party.id))!;
    final decoded = PartyCodec.partyFromJson(await crypto.decryptJson(snap.party));
    expect(decoded.title, 'Where to?');

    final peerBallot =
        Ballot.approval(id: 'peer', party: decoded, approvedOptionIds: const ['b']);
    await peer.submitBallot(party.id, 'peer',
        await crypto.encryptJson(PartyCodec.ballotToJson(peerBallot)));

    // Host folds the peer's encrypted vote into its local tally.
    await controller.syncToLocal();
    final result = await repo.computeResult(party.id) as ApprovalResult;
    expect(result.ballotCount, 2); // host + peer
    expect(result.tallies.firstWhere((t) => t.optionId == 'a').approvals, 1);
    expect(result.tallies.firstWhere((t) => t.optionId == 'b').approvals, 1);
    expect(controller.peerCount, 1);
  });

  test('a grouped party travels with its manifest and gathers roster names',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPartyRepository(db);
    final groups = GroupRepositoryImpl(db);
    await groups.createGroup(name: 'The household', id: 'g1');

    final party = await repo.createParty(
      title: 'Where do we live?',
      options: const [
        PartyOption(id: 'a', label: 'City'),
        PartyOption(id: 'b', label: 'Cabin'),
      ],
      votingMethod: VotingMethod.approval,
      groupId: 'g1',
      considered: true,
    );

    final controller =
        LanHostController(repo, InMemoryPartyKeyStore(), groups);
    addTearDown(controller.stop);
    final hosted = await controller.start(party.id);
    final key = PartyJoinLink.parse(hosted.joinLink)!.keyString;

    // A peer fetches the blob: the manifest and considered flag ride inside.
    final channel = await connectToLanHost('127.0.0.1', hosted.port);
    final peer = ChannelPartyRelay(channel);
    addTearDown(peer.dispose);
    final crypto = PartyCrypto.fromKeyString(key);
    final snap = (await peer.fetchParty(party.id))!;
    final json = await crypto.decryptJson(snap.party);
    final manifest = PartyCodec.groupManifestOf(json);
    expect(manifest, isNotNull);
    expect(manifest!.name, 'The household');
    final decoded = PartyCodec.partyFromJson(json);
    expect(decoded.considered, isTrue);
    expect(decoded.groupId, 'g1');

    // The peer votes attributed; syncToLocal folds the vote in AND teaches
    // the host's roster who Ada is.
    final peerBallot = Ballot.approval(
        id: 'peer-ada',
        party: decoded,
        approvedOptionIds: const ['b'],
        memberId: 'm-ada');
    await peer.submitBallot(
      party.id,
      'peer-ada',
      await crypto.encryptJson(
          PartyCodec.ballotToJson(peerBallot, memberDisplayName: 'Ada')),
    );
    await controller.syncToLocal();

    final ballots = await repo.getBallots(party.id);
    expect(ballots.single.memberId, 'm-ada');
    final roster = await groups.membersOf('g1');
    expect(roster.map((m) => m.displayName), contains('Ada'));
  });

  test('a repeat sync does not re-merge ballots it already folded in', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPartyRepository(db);
    final party = await repo.createParty(
      title: 'Where to?',
      options: const [
        PartyOption(id: 'a', label: 'Park'),
        PartyOption(id: 'b', label: 'Pub'),
      ],
      votingMethod: VotingMethod.approval,
    );
    final controller =
        LanHostController(repo, InMemoryPartyKeyStore(), GroupRepositoryImpl(db));
    addTearDown(controller.stop);
    final hosted = await controller.start(party.id);
    final key = PartyJoinLink.parse(hosted.joinLink)!.keyString;

    final channel = await connectToLanHost('127.0.0.1', hosted.port);
    final peer = ChannelPartyRelay(channel);
    addTearDown(peer.dispose);
    final crypto = PartyCrypto.fromKeyString(key);
    final decoded = PartyCodec.partyFromJson(
        await crypto.decryptJson((await peer.fetchParty(party.id))!.party));
    await peer.submitBallot(
        party.id,
        'peer',
        await crypto.encryptJson(PartyCodec.ballotToJson(Ballot.approval(
            id: 'peer', party: decoded, approvedOptionIds: const ['b']))));

    await controller.syncToLocal();
    expect(await repo.getBallots(party.id), hasLength(1));

    // Remove the merged row behind the controller's back. The host's store is
    // unchanged, so a second sync has nothing new and must not touch the
    // database again (the old loop re-decrypted and re-inserted every ballot
    // on every 2 second tick).
    await db.delete(db.partyBallots).go();
    await controller.syncToLocal();
    expect(await repo.getBallots(party.id), isEmpty);
  });
}
