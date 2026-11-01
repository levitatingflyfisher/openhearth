// Rotation on membership change (BUILD-SPEC §3.6). W2 acceptance:
// remove → rotate locks the departed member out of BOTH the key and the new
// channel address; silent leave → deterministic successor rotates;
// concurrent-rotation convergence under any delivery order (property);
// rekey-request self-heal.
import 'dart:math';
import 'dart:typed_data';

import 'package:porch_app/domain/envelope.dart';
import 'package:porch_app/domain/identity.dart';
import 'package:porch_app/domain/keyring.dart';
import 'package:porch_app/domain/roster.dart';
import 'package:porch_app/domain/rotation.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late SodiumSumo sodium;
  late PorchIdentity alice, bob, carol, mallory;

  RosterEntry entryFor(PorchIdentity id, String name,
          {required int joinedAt, bool isAdmin = false}) =>
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

  // Fresh 3-member group state per test.
  late Uint8List gk1;
  late Roster abc;
  setUp(() {
    gk1 = mintGroupKey(sodium);
    abc = Roster(members: [
      entryFor(alice, 'Alice', joinedAt: 100, isAdmin: true),
      entryFor(bob, 'Bob', joinedAt: 200),
      entryFor(carol, 'Carol', joinedAt: 300),
    ]);
  });

  group('departure triggers (§3.6 step 1; joins do NOT rotate, §3.5 step 6)',
      () {
    test('REMOVE and LEAVE yield a departure; JOIN/PROFILE/TRANSFER do not',
        () {
      expect(
          departureOf(RemoveOp(
              senderSignPk: alice.sign.publicKey,
              seq: 1,
              issuedAt: 0,
              memberPk: bob.sign.publicKey)),
          bob.sign.publicKey);
      expect(
          departureOf(LeaveOp(
              senderSignPk: carol.sign.publicKey, seq: 1, issuedAt: 0)),
          carol.sign.publicKey);
      expect(
          departureOf(JoinOp(
              senderSignPk: alice.sign.publicKey,
              seq: 1,
              issuedAt: 0,
              member: entryFor(mallory, 'x', joinedAt: 1))),
          isNull);
      expect(
          departureOf(ProfileOp(
              senderSignPk: bob.sign.publicKey,
              seq: 1,
              issuedAt: 0,
              displayName: 'B')),
          isNull);
      expect(
          departureOf(TransferAdminOp(
              senderSignPk: alice.sign.publicKey,
              seq: 1,
              issuedAt: 0,
              toPk: bob.sign.publicKey)),
          isNull);
    });
  });

  group('rotator election (§3.6 step 2 — same rule as roster succession)', () {
    test('member departs → the current admin rotates', () {
      expect(electRotator(abc, departedPk: bob.sign.publicKey),
          alice.sign.publicKey);
    });

    test('admin departs → oldest remaining member rotates (and is admin)',
        () {
      expect(electRotator(abc, departedPk: alice.sign.publicKey),
          bob.sign.publicKey);
    });
  });

  group('remove → rotate (W2 acceptance)', () {
    test('departed member gets no bundle, cannot decrypt e+1, cannot even '
        'address the new channel', () {
      // Alice (admin) removes Bob.
      final postRoster = foldRoster(abc, [
        RemoveOp(
            senderSignPk: alice.sign.publicKey,
            seq: 10,
            issuedAt: 1000,
            memberPk: bob.sign.publicKey),
      ]).roster;

      final gk2 = mintGroupKey(sodium);
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: postRoster,
          rotatorSign: alice.sign,
          issuedAt: 1001,
          oldEpoch: 1,
          oldGk: gk1);

      // Fan-out goes to every remaining member except the rotator — and
      // pointedly NOT to Bob.
      expect(fanout.mailboxBlobs.keys,
          unorderedEquals([deriveMailboxId(sodium, carol.sign.publicKey)]));

      // Carol opens and validates her bundle.
      final bundle = openRotationBundle(sodium,
          myBox: carol.box, sealed: fanout.mailboxBlobs.values.single);
      expect(bundle, isNotNull);
      expect(bundle!.epoch, 2);
      expect(bundle.gk, gk2);
      expect(bundle.rotatorSignPk, alice.sign.publicKey);
      expect(
          validateRotation(bundle,
              localRoster: abc,
              currentEpoch: 1,
              departedPk: bob.sign.publicKey),
          isTrue);

      // Bob cannot open Carol's sealed bundle.
      expect(
          openRotationBundle(sodium,
              myBox: bob.box, sealed: fanout.mailboxBlobs.values.single),
          isNull);

      // One stroke, two revocations: Bob can neither decrypt epoch 2...
      final carolKeyring = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: bundle.gk, nowSec: 1002);
      final e2wire = sealEnvelope(sodium,
          type: 'presence',
          fields: {'status': 'on'},
          issuedAt: 1003,
          epoch: 2,
          gk: gk2,
          senderSign: carol.sign);
      final bobKeyring = GroupKeyring.genesis(gk1); // all Bob ever had
      expect(openEnvelope(sodium, wire: e2wire, keyring: bobKeyring), isNull);

      // ...nor compute where the group even lives now.
      expect(deriveChannelId(sodium, gk2),
          isNot(deriveChannelId(sodium, gk1)));

      // Grace: a straggler's old-epoch event still renders for Carol.
      final oldWire = sealEnvelope(sodium,
          type: 'presence',
          fields: {'status': 'on', 'tag': '🚗'},
          issuedAt: 1004,
          epoch: 1,
          gk: gk1,
          senderSign: alice.sign);
      final opened =
          openEnvelope(sodium, wire: oldWire, keyring: carolKeyring);
      expect(opened, isNotNull);
      expect(opened!.fields['tag'], '🚗');
    });

    test('bulletin duplicate: members extract their box; the departed member '
        'can open the outer envelope but has no inner box (§3.6 step 3)', () {
      final postRoster = foldRoster(abc, [
        RemoveOp(
            senderSignPk: alice.sign.publicKey,
            seq: 10,
            issuedAt: 1000,
            memberPk: bob.sign.publicKey),
      ]).roster;
      final gk2 = mintGroupKey(sodium);
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: postRoster,
          rotatorSign: alice.sign,
          issuedAt: 1001,
          oldEpoch: 1,
          oldGk: gk1);

      // The dup rides the OLD channel: outer envelope opens with gk1.
      final outer = openEnvelope(sodium,
          wire: fanout.bulletinDupEnvelope,
          keyring: GroupKeyring.genesis(gk1));
      expect(outer, isNotNull);
      expect(outer!.type, 'ROTATION');

      // Carol finds her box and recovers the same bundle.
      final viaDup = rotationFromDupEnvelope(sodium,
          env: outer, myBox: carol.box, mySignPk: carol.sign.publicKey);
      expect(viaDup, isNotNull);
      expect(viaDup!.gk, gk2);

      // Bob (departed, still holds gk1) opened the outer too — but there is
      // no box addressed to him, and Carol's box will not open for him.
      expect(
          rotationFromDupEnvelope(sodium,
              env: outer, myBox: bob.box, mySignPk: bob.sign.publicKey),
          isNull);
    });
  });

  group('silent leave → successor rotates (W2 acceptance)', () {
    test('admin leaves; bob (oldest) rotates; carol validates', () {
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster;
      expect(postRoster.adminPk, bob.sign.publicKey);

      final gk2 = mintGroupKey(sodium);
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: postRoster,
          rotatorSign: bob.sign,
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final bundle = openRotationBundle(sodium,
          myBox: carol.box,
          sealed:
              fanout.mailboxBlobs[deriveMailboxId(sodium, carol.sign.publicKey)]!);
      expect(bundle, isNotNull);
      expect(
          validateRotation(bundle!,
              localRoster: abc,
              currentEpoch: 1,
              departedPk: alice.sign.publicKey),
          isTrue,
          reason: 'bob is the deterministic successor of the departed admin');
    });

    test('a bundle from anyone but the expected rotator is rejected', () {
      // Carol tries to rotate after Alice's leave — but Bob is older.
      final gk2 = mintGroupKey(sodium);
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster;
      final rogue = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: postRoster,
          rotatorSign: carol.sign,
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final bundle = openRotationBundle(sodium,
          myBox: bob.box,
          sealed:
              rogue.mailboxBlobs[deriveMailboxId(sodium, bob.sign.publicKey)]!);
      expect(
          validateRotation(bundle!,
              localRoster: abc,
              currentEpoch: 1,
              departedPk: alice.sign.publicKey),
          isFalse);

      // And a complete outsider is rejected even with a well-formed bundle.
      final outsider = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: mintGroupKey(sodium),
          postRoster: postRoster,
          rotatorSign: mallory.sign,
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final malBundle = openRotationBundle(sodium,
          myBox: bob.box,
          sealed: outsider
              .mailboxBlobs[deriveMailboxId(sodium, bob.sign.publicKey)]!);
      expect(
          validateRotation(malBundle!,
              localRoster: abc,
              currentEpoch: 1,
              departedPk: alice.sign.publicKey),
          isFalse);
    });

    test('tampered sealed bundle → null; sig by another key → null', () {
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster;
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: mintGroupKey(sodium),
          postRoster: postRoster,
          rotatorSign: bob.sign,
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final sealed =
          fanout.mailboxBlobs[deriveMailboxId(sodium, carol.sign.publicKey)]!;
      final bad = Uint8List.fromList(sealed)..[12] ^= 0x40;
      expect(openRotationBundle(sodium, myBox: carol.box, sealed: bad), isNull);

      final forged = forgeRotationBundleForTest(sodium,
          groupUuid: 'g1',
          epoch: 2,
          gk: mintGroupKey(sodium),
          roster: postRoster,
          issuedAt: 0,
          claimedRotatorPk: bob.sign.publicKey,
          actualSigner: mallory.sign,
          recipientBoxPk: carol.box.publicKey);
      expect(openRotationBundle(sodium, myBox: carol.box, sealed: forged),
          isNull);
    });
  });

  group('concurrent-rotation convergence (property, W2 acceptance)', () {
    test('any delivery order/interleaving → identical final epoch and key',
        () {
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster;

      RotationBundle bundleBy(PorchIdentity rotator, Uint8List gk) {
        final f = buildRotation(sodium,
            groupUuid: 'g1',
            newEpoch: 2,
            newGk: gk,
            postRoster: postRoster,
            rotatorSign: rotator.sign,
            issuedAt: 2001,
            oldEpoch: 1,
            oldGk: gk1);
        // Open as carol (recipient common to both rotators' fan-outs).
        return openRotationBundle(sodium,
            myBox: carol.box,
            sealed: f
                .mailboxBlobs[deriveMailboxId(sodium, carol.sign.publicKey)]!)!;
      }

      final gkA = mintGroupKey(sodium);
      final gkB = mintGroupKey(sodium);
      final gkC = mintGroupKey(sodium);
      // Race: bob's bundle landed on the bulletin at seq 31; a duplicate of
      // the same at seq 34; plus two mailbox-only bundles (no seq).
      final candidates = [
        RotationCandidate(bundle: bundleBy(bob, gkA), seq: 34),
        RotationCandidate(bundle: bundleBy(bob, gkB), seq: 31),
        RotationCandidate(bundle: bundleBy(bob, gkC), seq: null),
      ];

      final rand = Random(7);
      final expected = electRotationWinner(sodium, candidates)!;
      expect(expected.bundle.gk, gkB, reason: 'lowest bulletin seq wins');
      for (var i = 0; i < 50; i++) {
        final shuffled = List.of(candidates)..shuffle(rand);
        final winner = electRotationWinner(sodium, shuffled)!;
        expect(winner.bundle.gk, expected.bundle.gk);
        expect(winner.seq, expected.seq);
      }
    });

    test('mailbox-only fallback: admin-authored wins, else smallest '
        'hash of the new key', () {
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster; // bob is now admin

      RotationBundle bundleBy(PorchIdentity rotator, Uint8List gk) {
        final f = buildRotation(sodium,
            groupUuid: 'g1',
            newEpoch: 2,
            newGk: gk,
            postRoster: postRoster,
            rotatorSign: rotator.sign,
            issuedAt: 2001,
            oldEpoch: 1,
            oldGk: gk1);
        // The rotator never seals a bundle to themselves — open as the
        // other remaining member.
        final recipient = identical(rotator, carol) ? bob : carol;
        return openRotationBundle(sodium,
            myBox: recipient.box,
            sealed: f.mailboxBlobs[
                deriveMailboxId(sodium, recipient.sign.publicKey)]!)!;
      }

      final gkAdmin = mintGroupKey(sodium);
      final gkOther = mintGroupKey(sodium);
      // Admin-authored (bob is admin of postRoster) vs non-admin authored.
      final withAdmin = [
        RotationCandidate(bundle: bundleBy(carol, gkOther), seq: null),
        RotationCandidate(bundle: bundleBy(bob, gkAdmin), seq: null),
      ];
      expect(electRotationWinner(sodium, withAdmin)!.bundle.gk, gkAdmin);

      // No admin in the race → smallest BLAKE2b(gk) decides, stably.
      final k1 = mintGroupKey(sodium);
      final k2 = mintGroupKey(sodium);
      final noAdmin = [
        RotationCandidate(bundle: bundleBy(carol, k1), seq: null),
        RotationCandidate(bundle: bundleBy(carol, k2), seq: null),
      ];
      final w1 = electRotationWinner(sodium, noAdmin)!;
      final w2 = electRotationWinner(sodium, noAdmin.reversed.toList())!;
      expect(b64(w1.bundle.gk), b64(w2.bundle.gk));
    });

    test('members applying the winner all land on the same keyring', () {
      final postRoster = foldRoster(abc, [
        LeaveOp(senderSignPk: alice.sign.publicKey, seq: 20, issuedAt: 2000),
      ]).roster;
      final gk2 = mintGroupKey(sodium);
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: postRoster,
          rotatorSign: bob.sign,
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final carolBundle = openRotationBundle(sodium,
          myBox: carol.box,
          sealed:
              fanout.mailboxBlobs[deriveMailboxId(sodium, carol.sign.publicKey)]!)!;

      final bobKeyring = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: gk2, nowSec: 2002); // rotator's own
      final carolKeyring = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: carolBundle.gk, nowSec: 2003);
      expect(b64(carolKeyring.current.gk), b64(bobKeyring.current.gk));
      expect(deriveChannelId(sodium, carolKeyring.current.gk),
          deriveChannelId(sodium, bobKeyring.current.gk));
    });
  });

  group('rekey-request self-heal (§3.6 step 6, W2 acceptance)', () {
    test('a member who missed rotation regains the current epoch', () {
      // Group rotated to epoch 2 (bob removed... no: nobody departed —
      // carol just missed the rotation that removed a fourth member; for
      // the domain test, the group state is simply: current = epoch 2).
      final gk2 = mintGroupKey(sodium);
      final aliceKeyring = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: gk2, nowSec: 3000);

      // Carol is stuck at epoch 1. She posts a signed REKEY_REQUEST on the
      // old channel bulletin.
      final request = buildRekeyRequestEnvelope(sodium,
          myBoxPk: carol.box.publicKey,
          issuedAt: 3100,
          epoch: 1,
          gk: gk1,
          senderSign: carol.sign);

      // Alice (still within grace for epoch 1) reads and validates it.
      final env =
          openEnvelope(sodium, wire: request, keyring: aliceKeyring)!;
      expect(env.type, 'REKEY_REQUEST');
      final req = rekeyRequestFromEnvelope(env, roster: abc);
      expect(req, isNotNull);

      // Any current member may re-grant (alice here), sealed to the
      // roster-verified boxPk.
      final regrant = buildRegrant(sodium,
          request: req!,
          groupUuid: 'g1',
          currentEpoch: 2,
          currentGk: gk2,
          roster: abc,
          responderSign: alice.sign,
          issuedAt: 3200);

      final bundle =
          openRotationBundle(sodium, myBox: carol.box, sealed: regrant);
      expect(bundle, isNotNull);
      expect(
          validateRotation(bundle!,
              localRoster: abc, currentEpoch: 1, selfHeal: true),
          isTrue,
          reason: 're-grants of an existing epoch may come from any member');

      final healed = GroupKeyring.genesis(gk1)
          .adopt(epoch: bundle.epoch, gk: bundle.gk, nowSec: 3300);
      expect(b64(healed.current.gk), b64(gk2));
    });

    test('request with a boxPk not matching the roster is refused '
        '(no exfiltration to a vandal address)', () {
      final request = buildRekeyRequestEnvelope(sodium,
          myBoxPk: mallory.box.publicKey, // lies about the box
          issuedAt: 3100,
          epoch: 1,
          gk: gk1,
          senderSign: carol.sign);
      final env = openEnvelope(sodium,
          wire: request, keyring: GroupKeyring.genesis(gk1))!;
      expect(rekeyRequestFromEnvelope(env, roster: abc), isNull);
    });

    test('request from a non-member is refused', () {
      final request = buildRekeyRequestEnvelope(sodium,
          myBoxPk: mallory.box.publicKey,
          issuedAt: 3100,
          epoch: 1,
          gk: gk1,
          senderSign: mallory.sign);
      final env = openEnvelope(sodium,
          wire: request, keyring: GroupKeyring.genesis(gk1))!;
      expect(rekeyRequestFromEnvelope(env, roster: abc), isNull);
    });

    test('unsolicited e+1 from a non-elected member is still rejected '
        'without the selfHeal flag', () {
      final gk2 = mintGroupKey(sodium);
      final fanout = buildRotation(sodium,
          groupUuid: 'g1',
          newEpoch: 2,
          newGk: gk2,
          postRoster: abc, // nobody departed
          rotatorSign: carol.sign, // carol is not the admin
          issuedAt: 2001,
          oldEpoch: 1,
          oldGk: gk1);
      final bundle = openRotationBundle(sodium,
          myBox: bob.box,
          sealed:
              fanout.mailboxBlobs[deriveMailboxId(sodium, bob.sign.publicKey)]!)!;
      expect(validateRotation(bundle, localRoster: abc, currentEpoch: 1),
          isFalse);
      expect(
          validateRotation(bundle,
              localRoster: abc, currentEpoch: 1, selfHeal: true),
          isTrue,
          reason: 'the SAME bundle heals a member who asked for it');
    });
  });
}
