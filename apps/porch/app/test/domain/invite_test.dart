// Invite handshake (BUILD-SPEC §3.5). W2 acceptance: full transcript
// mint → escrow → join → fulfill → grant → Bob decrypts, verifies granter
// sig, derives channelId; orphaned invite fulfilled by an admin via escrow;
// terminal void → regenerate.
//
// Trust story under test: the token t rides the link fragment and NEVER
// touches the server; everything the server stores is ciphertext to it.
import 'dart:typed_data';

import 'package:porch_app/domain/envelope.dart';
import 'package:porch_app/domain/identity.dart';
import 'package:porch_app/domain/invite.dart';
import 'package:porch_app/domain/keyring.dart';
import 'package:porch_app/domain/roster.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late SodiumSumo sodium;
  late PorchIdentity alice, bob, carol, mallory;

  RosterEntry entryFor(PorchIdentity id, String name,
          {int joinedAt = 0, bool isAdmin = false}) =>
      RosterEntry(
        signPk: id.sign.publicKey,
        boxPk: id.box.publicKey,
        displayName: name,
        contactNote: '',
        joinedAt: joinedAt,
        isAdmin: isAdmin,
      );

  setUpAll(() async {
    sodium = await loadTestSodium();
    Uint8List e(int n) => Uint8List.fromList(List.filled(16, n));
    alice = PorchIdentity.fromEntropy(sodium, e(1));
    bob = PorchIdentity.fromEntropy(sodium, e(2));
    carol = PorchIdentity.fromEntropy(sodium, e(3));
    mallory = PorchIdentity.fromEntropy(sodium, e(66));
  });

  group('token derivations (§3.5)', () {
    test('inviteId is 22 chars, deterministic, token-bound', () {
      final t = InviteToken.mint(sodium);
      expect(t.inviteId(sodium), hasLength(22));
      expect(t.inviteId(sodium), t.inviteId(sodium));
      expect(t.inviteId(sodium),
          isNot(InviteToken.mint(sodium).inviteId(sodium)));
    });

    test('id, key, fetchProof, grantProof are domain-separated', () {
      final t = InviteToken.mint(sodium);
      final values = {
        t.inviteId(sodium),
        b64(t.inviteKey(sodium)),
        t.fetchProof(sodium),
        t.grantProof(sodium),
      };
      expect(values, hasLength(4), reason: 'no two derivations may collide');
    });

    test('proofs are derivable ONLY with t (32 random bytes)', () {
      expect(InviteToken.mint(sodium).t, hasLength(32));
      expect(InviteToken.mint(sodium).t,
          isNot(equals(InviteToken.mint(sodium).t)));
    });
  });

  group('link and paste-code', () {
    test('porch://i#<id>.<t> round-trips', () {
      final t = InviteToken.mint(sodium);
      final link = t.toLink(sodium);
      expect(link, startsWith('porch://i#'));
      final parsed = InviteToken.parse(sodium, link);
      expect(parsed, isNotNull);
      expect(parsed!.t, t.t);
    });

    test('bare pasted code round-trips (primary tested path)', () {
      final t = InviteToken.mint(sodium);
      final code = t.toCode(sodium);
      expect(InviteToken.parse(sodium, code)!.t, t.t);
      expect(InviteToken.parse(sodium, '  $code  ')!.t, t.t,
          reason: 'humans paste with whitespace');
    });

    test('rejects garbage, wrong id, truncated token', () {
      final t = InviteToken.mint(sodium);
      final other = InviteToken.mint(sodium);
      expect(InviteToken.parse(sodium, 'not a link'), isNull);
      expect(InviteToken.parse(sodium, ''), isNull);
      // id from one invite glued to the token of another → reject.
      final franken =
          'porch://i#${t.inviteId(sodium)}.${b64urlNoPad(other.t)}';
      expect(InviteToken.parse(sodium, franken), isNull);
      final short =
          'porch://i#${t.inviteId(sodium)}.${b64urlNoPad(t.t).substring(0, 10)}';
      expect(InviteToken.parse(sodium, short), isNull);
    });
  });

  group('join blob (§3.5 step 3)', () {
    test('Bob → secretbox intro → Alice reads it with k_i', () {
      final t = InviteToken.mint(sodium);
      final blob = buildJoinBlob(sodium,
          token: t,
          signPk: bob.sign.publicKey,
          boxPk: bob.box.publicKey,
          displayName: 'Bob',
          contactNote: 'Signal: @bob');
      final intro = openJoinBlob(sodium, token: t, blob: blob);
      expect(intro, isNotNull);
      expect(intro!.signPk, bob.sign.publicKey);
      expect(intro.boxPk, bob.box.publicKey);
      expect(intro.displayName, 'Bob');
      expect(intro.contactNote, 'Signal: @bob');
    });

    test('tampered blob or wrong token → null', () {
      final t = InviteToken.mint(sodium);
      final blob = buildJoinBlob(sodium,
          token: t,
          signPk: bob.sign.publicKey,
          boxPk: bob.box.publicKey,
          displayName: 'Bob',
          contactNote: '');
      final bad = Uint8List.fromList(blob)..[30] ^= 1;
      expect(openJoinBlob(sodium, token: t, blob: bad), isNull);
      expect(
          openJoinBlob(sodium, token: InviteToken.mint(sodium), blob: blob),
          isNull);
    });
  });

  group('full transcript (W2 acceptance)', () {
    test('mint → join → fulfill → grant → Bob verifies + derives channelId',
        () {
      // Alice's group: epoch 1, roster [alice(admin)].
      final gk = mintGroupKey(sodium);
      final keyring = GroupKeyring.genesis(gk);
      var roster = Roster.genesis(entryFor(alice, 'Alice', isAdmin: true));

      // 1. Alice mints; only inviteId would be registered server-side.
      final t = InviteToken.mint(sodium);

      // 3. Bob (own seed, no server identity) posts his sealed intro.
      final joinBlob = buildJoinBlob(sodium,
          token: t,
          signPk: bob.sign.publicKey,
          boxPk: bob.box.publicKey,
          displayName: 'Bob',
          contactNote: 'just call me');

      // 4. Alice fetches (fetchProof gate is the relay's job), decrypts,
      //    adds Bob to the roster, posts the grant.
      final intro = openJoinBlob(sodium, token: t, blob: joinBlob)!;
      roster = foldRoster(roster, [
        JoinOp(
          senderSignPk: alice.sign.publicKey,
          seq: 1,
          issuedAt: 500,
          member: RosterEntry(
            signPk: intro.signPk,
            boxPk: intro.boxPk,
            displayName: intro.displayName,
            contactNote: intro.contactNote,
            joinedAt: 500,
            isAdmin: false,
          ),
        ),
      ]).roster;

      final grantBlob = buildGrantBlob(sodium,
          recipientBoxPk: intro.boxPk,
          groupUuid: 'g-uuid-1',
          groupName: 'My Porch',
          epoch: keyring.current.epoch,
          gk: keyring.current.gk,
          roster: roster,
          grantedAt: 600,
          granterSign: alice.sign);

      // 5. Bob completes: opens the grant, verifies granter, derives channel.
      final grant = openGrantBlob(sodium, myBox: bob.box, blob: grantBlob);
      expect(grant, isNotNull);
      expect(grant!.groupUuid, 'g-uuid-1');
      expect(grant.groupName, 'My Porch');
      expect(grant.epoch, 1);
      expect(grant.gk, gk);
      expect(grant.granterSignPk, alice.sign.publicKey);
      expect(grant.roster.isMember(bob.sign.publicKey), isTrue);

      // Bob's derived wire address matches Alice's — same group, same key.
      expect(deriveChannelId(sodium, grant.gk), deriveChannelId(sodium, gk));

      // And Bob can now read a presence envelope Alice seals.
      final wire = sealEnvelope(sodium,
          type: 'presence',
          fields: {'status': 'on', 'tag': '🚶'},
          issuedAt: 700,
          epoch: 1,
          gk: gk,
          senderSign: alice.sign);
      final bobKeyring =
          GroupKeyring.fromGrant(epoch: grant.epoch, gk: grant.gk);
      final opened = openEnvelope(sodium, wire: wire, keyring: bobKeyring);
      expect(opened, isNotNull);
      expect(opened!.fields['tag'], '🚶');
    });
  });

  group('escrow (§3.5 step 2 — inviter-left insurance)', () {
    test('admin recovers t from the pinned escrow and fulfills', () {
      final gk = mintGroupKey(sodium);
      final keyring = GroupKeyring.genesis(gk);
      final roster = Roster(members: [
        entryFor(alice, 'Alice', joinedAt: 1),
        entryFor(carol, 'Carol', joinedAt: 2, isAdmin: true),
      ]);

      final t = InviteToken.mint(sodium);
      final escrowWire = buildEscrowEnvelope(sodium,
          token: t,
          expiresAt: 999999,
          issuedAt: 100,
          epoch: 1,
          gk: gk,
          senderSign: alice.sign);

      // Later: Alice is gone. Carol (admin) folds the bulletin.
      final env = openEnvelope(sodium, wire: escrowWire, keyring: keyring)!;
      expect(env.type, 'ESCROW');
      expect(roster.isMember(env.senderSignPk), isTrue);
      final escrow = escrowFromEnvelope(sodium, env);
      expect(escrow, isNotNull);
      expect(escrow!.token.t, t.t);
      expect(escrow.inviteId, t.inviteId(sodium));
      expect(escrow.expiresAt, 999999);

      // Carol can now compute the proofs (fetch/grant gates) and fulfill:
      expect(escrow.token.fetchProof(sodium), t.fetchProof(sodium));

      // ... and Bob's grant verifies against Carol as granter.
      final joinBlob = buildJoinBlob(sodium,
          token: t,
          signPk: bob.sign.publicKey,
          boxPk: bob.box.publicKey,
          displayName: 'Bob',
          contactNote: '');
      final intro = openJoinBlob(sodium, token: escrow.token, blob: joinBlob)!;
      final postJoin = foldRoster(roster, [
        JoinOp(
            senderSignPk: carol.sign.publicKey,
            seq: 5,
            issuedAt: 500,
            member: RosterEntry(
                signPk: intro.signPk,
                boxPk: intro.boxPk,
                displayName: intro.displayName,
                contactNote: intro.contactNote,
                joinedAt: 500,
                isAdmin: false)),
      ]).roster;
      final grant = openGrantBlob(sodium,
          myBox: bob.box,
          blob: buildGrantBlob(sodium,
              recipientBoxPk: intro.boxPk,
              groupUuid: 'g',
              groupName: 'My Porch',
              epoch: 1,
              gk: gk,
              roster: postJoin,
              grantedAt: 600,
              granterSign: carol.sign));
      expect(grant, isNotNull);
      expect(grant!.granterSignPk, carol.sign.publicKey);
    });

    test('escrow with a token that does not match its inviteId → null', () {
      final gk = mintGroupKey(sodium);
      final t = InviteToken.mint(sodium);
      final other = InviteToken.mint(sodium);
      // Vandal posts an escrow whose inviteId belongs to a different token.
      final wire = sealEnvelope(sodium,
          type: 'ESCROW',
          fields: {
            't': b64(t.t),
            'inviteId': other.inviteId(sodium),
            'expiresAt': 1,
          },
          issuedAt: 0,
          epoch: 1,
          gk: gk,
          senderSign: mallory.sign);
      final env =
          openEnvelope(sodium, wire: wire, keyring: GroupKeyring.genesis(gk))!;
      expect(escrowFromEnvelope(sodium, env), isNull);
    });
  });

  group('grant rejection (a compromised server cannot forge a grant)', () {
    late Uint8List gk;
    late Roster roster;
    setUp(() {
      gk = mintGroupKey(sodium);
      roster = Roster(members: [
        entryFor(alice, 'Alice', joinedAt: 1, isAdmin: true),
        entryFor(bob, 'Bob', joinedAt: 2),
      ]);
    });

    Uint8List grantBy(KeyPair granterSign) => buildGrantBlob(sodium,
        recipientBoxPk: bob.box.publicKey,
        groupUuid: 'g',
        groupName: 'n',
        epoch: 1,
        gk: gk,
        roster: roster,
        grantedAt: 0,
        granterSign: granterSign);

    test('tampered sealed blob → null', () {
      final blob = grantBy(alice.sign);
      final bad = Uint8List.fromList(blob)..[8] ^= 0xff;
      expect(openGrantBlob(sodium, myBox: bob.box, blob: bad), isNull);
    });

    test('sealed to someone else → null for Bob', () {
      final blob = buildGrantBlob(sodium,
          recipientBoxPk: carol.box.publicKey,
          groupUuid: 'g',
          groupName: 'n',
          epoch: 1,
          gk: gk,
          roster: roster,
          grantedAt: 0,
          granterSign: alice.sign);
      expect(openGrantBlob(sodium, myBox: bob.box, blob: blob), isNull);
    });

    test('granter not in the delivered roster → null (TOFU check)', () {
      expect(openGrantBlob(sodium, myBox: bob.box, blob: grantBy(mallory.sign)),
          isNull);
    });
  });

  group('invite state machine (incl. void — regenerate, gate 4)', () {
    PendingInvite fresh() => PendingInvite(
        inviteId: 'id-1',
        t: Uint8List.fromList(List.filled(32, 7)),
        expiresAt: 1000,
        status: InviteStatus.open);

    test('open → joined → granted is the happy path', () {
      final p = fresh().markJoined().markGranted();
      expect(p.status, InviteStatus.granted);
    });

    test('open or joined can void; void and granted are terminal', () {
      expect(fresh().markVoided().status, InviteStatus.voided);
      expect(fresh().markJoined().markVoided().status, InviteStatus.voided);
      expect(() => fresh().markVoided().markJoined(), throwsStateError);
      expect(() => fresh().markJoined().markGranted().markVoided(),
          throwsStateError);
    });

    test('skipping joined is illegal (grant needs a join blob)', () {
      expect(() => fresh().markGranted(), throwsStateError);
    });

    test('expiry check is pure and honest', () {
      expect(fresh().isExpired(999), isFalse);
      expect(fresh().isExpired(1000), isFalse);
      expect(fresh().isExpired(1001), isTrue);
    });

    test('regenerate mints a genuinely fresh invite (one tap by anyone)', () {
      final voided = fresh().markVoided();
      final regenerated = regenerateInvite(sodium, voided,
          nowSec: 2000, ttlSeconds: 72 * 3600);
      expect(regenerated.status, InviteStatus.open);
      expect(regenerated.t, isNot(equals(voided.t)));
      expect(regenerated.inviteId, isNot(voided.inviteId));
      expect(regenerated.expiresAt, 2000 + 72 * 3600);
    });
  });
}
