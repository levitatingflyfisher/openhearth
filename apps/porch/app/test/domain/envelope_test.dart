// Envelope codec (BUILD-SPEC §3.3) — sign-then-encrypt, AD-bound to
// channel + epoch. W1 acceptance: round-trip; AD tamper → reject; wrong
// epoch → reject; forged/absent signature → reject; grace-epoch decrypt
// works; epoch-prune policy honored.
import 'dart:convert';
import 'dart:typed_data';

import 'package:porch_app/domain/envelope.dart';
import 'package:porch_app/domain/identity.dart';
import 'package:porch_app/domain/keyring.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:porch_app/domain/support/canonical_json.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late SodiumSumo sodium;
  late PorchIdentity alice;
  late PorchIdentity mallory;
  final gk1 = Uint8List.fromList(List.filled(32, 0xa1));
  final gk2 = Uint8List.fromList(List.filled(32, 0xa2));

  setUpAll(() async {
    sodium = await loadTestSodium();
    alice = PorchIdentity.fromEntropy(
        sodium, Uint8List.fromList(List.filled(16, 1)));
    mallory = PorchIdentity.fromEntropy(
        sodium, Uint8List.fromList(List.filled(16, 66)));
  });

  Uint8List seal({int epoch = 1, Uint8List? gk, String type = 'presence'}) =>
      sealEnvelope(
        sodium,
        type: type,
        fields: {'status': 'on', 'tag': '🚶'},
        issuedAt: 1700000000,
        epoch: epoch,
        gk: gk ?? gk1,
        senderSign: alice.sign,
      );

  group('round-trip', () {
    test('seal → open returns payload, sender, epoch, type', () {
      final opened = openEnvelope(sodium,
          wire: seal(), keyring: GroupKeyring.genesis(gk1));
      expect(opened, isNotNull);
      expect(opened!.type, 'presence');
      expect(opened.epoch, 1);
      expect(opened.issuedAt, 1700000000);
      expect(opened.senderSignPk, alice.sign.publicKey);
      expect(opened.fields['status'], 'on');
      expect(opened.fields['tag'], '🚶');
      expect(opened.fields.containsKey('senderSignPk'), isFalse,
          reason: 'reserved keys are lifted out of fields');
    });

    test('two seals of the same payload differ on the wire (fresh nonce)',
        () {
      expect(seal(), isNot(equals(seal())));
    });

    test('reserved field names are rejected at seal time', () {
      expect(
          () => sealEnvelope(sodium,
              type: 'x',
              fields: {'epoch': 9},
              issuedAt: 0,
              epoch: 1,
              gk: gk1,
              senderSign: alice.sign),
          throwsArgumentError);
    });
  });

  group('grace + prune (§3.2 step 3)', () {
    test('blob sealed under the previous epoch still opens after rotation',
        () {
      final old = seal(epoch: 1, gk: gk1);
      final rotated = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: gk2, nowSec: 1000);
      final opened = openEnvelope(sodium, wire: old, keyring: rotated);
      expect(opened, isNotNull);
      expect(opened!.epoch, 1);
    });

    test('blob under an epoch the keyring pruned is dropped', () {
      final old = seal(epoch: 1, gk: gk1);
      final pruned = GroupKeyring.genesis(gk1)
          .adopt(epoch: 2, gk: gk2, nowSec: 1000)
          .prune(1000 + 7 * 86400 + 1);
      expect(openEnvelope(sodium, wire: old, keyring: pruned), isNull);
    });

    test('wrong key entirely → dropped', () {
      final foreign = seal(gk: Uint8List.fromList(List.filled(32, 0xff)));
      expect(
          openEnvelope(sodium,
              wire: foreign, keyring: GroupKeyring.genesis(gk1)),
          isNull);
    });
  });

  group('tamper cases (all must DROP, §3.3)', () {
    test('any flipped ciphertext byte → dropped', () {
      final wire = seal();
      for (final i in [0, 10, 24, 30, wire.length - 1]) {
        final bad = Uint8List.fromList(wire);
        bad[i] ^= 0x01;
        expect(
            openEnvelope(sodium,
                wire: bad, keyring: GroupKeyring.genesis(gk1)),
            isNull,
            reason: 'flip at byte $i must not open');
      }
    });

    test('truncated / undersized wire → dropped, no throw', () {
      for (final n in [0, 1, 23, 24, 30]) {
        expect(
            openEnvelope(sodium,
                wire: Uint8List(n), keyring: GroupKeyring.genesis(gk1)),
            isNull);
      }
    });

    test('valid AEAD but forged signature → dropped', () {
      // Mallory encrypts with the (stolen) group key but cannot sign as
      // Alice: payload claims alice.sign.publicKey, sig is by Mallory.
      final payload = {
        'v': 1,
        'type': 'presence',
        'status': 'on',
        'issuedAt': 1700000000,
        'epoch': 1,
        'senderSignPk': b64(alice.sign.publicKey),
      };
      final sig = sodium.crypto.sign.detached(
          message: canonicalJsonBytes(payload),
          secretKey: mallory.sign.secretKey);
      final wire = rawSealForTest(sodium,
          payload: payload, sig: sig, epoch: 1, gk: gk1);
      expect(
          openEnvelope(sodium,
              wire: wire, keyring: GroupKeyring.genesis(gk1)),
          isNull);
    });

    test('payload epoch contradicting the AD epoch → dropped', () {
      final payload = {
        'v': 1,
        'type': 'presence',
        'status': 'on',
        'issuedAt': 1700000000,
        'epoch': 7, // lies: encrypted under epoch 1
        'senderSignPk': b64(alice.sign.publicKey),
      };
      final sig = sodium.crypto.sign.detached(
          message: canonicalJsonBytes(payload),
          secretKey: alice.sign.secretKey);
      final wire = rawSealForTest(sodium,
          payload: payload, sig: sig, epoch: 1, gk: gk1);
      expect(
          openEnvelope(sodium,
              wire: wire, keyring: GroupKeyring.genesis(gk1)),
          isNull);
    });

    test('non-JSON plaintext inside a valid AEAD → dropped', () {
      final wire = rawAeadForTest(sodium,
          plaintext: utf8.encode('not json'), epoch: 1, gk: gk1);
      expect(
          openEnvelope(sodium,
              wire: wire, keyring: GroupKeyring.genesis(gk1)),
          isNull);
    });
  });
}
