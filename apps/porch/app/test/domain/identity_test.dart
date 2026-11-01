// Identity & recovery (BUILD-SPEC §3.1): one 16-byte entropy is the whole
// identity. Everything below must be deterministic from it — that IS the
// recovery story.
import 'dart:convert';
import 'dart:typed_data';

import 'package:porch_app/domain/identity.dart';
import 'package:porch_app/domain/mnemonic.dart';
import 'package:porch_app/domain/support/bip39_words.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late SodiumSumo sodium;
  setUpAll(() async {
    sodium = await loadTestSodium();
  });

  Uint8List entropyOf(int fill) => Uint8List.fromList(List.filled(16, fill));

  group('PorchIdentity.fromEntropy', () {
    test('same entropy twice → byte-identical keypairs (W1 acceptance)', () {
      final a = PorchIdentity.fromEntropy(sodium, entropyOf(0x42));
      final b = PorchIdentity.fromEntropy(sodium, entropyOf(0x42));
      expect(a.sign.publicKey, b.sign.publicKey);
      expect(a.box.publicKey, b.box.publicKey);
      expect(a.sign.secretKey.extractBytes(), b.sign.secretKey.extractBytes());
      expect(a.box.secretKey.extractBytes(), b.box.secretKey.extractBytes());
      expect(a.mailboxId, b.mailboxId);
    });

    test('different entropy → different keys', () {
      final a = PorchIdentity.fromEntropy(sodium, entropyOf(1));
      final b = PorchIdentity.fromEntropy(sodium, entropyOf(2));
      expect(a.sign.publicKey, isNot(equals(b.sign.publicKey)));
      expect(a.box.publicKey, isNot(equals(b.box.publicKey)));
    });

    test('sign and box keys are independent (no Ed→X conversion)', () {
      final id = PorchIdentity.fromEntropy(sodium, entropyOf(9));
      expect(id.sign.publicKey, isNot(equals(id.box.publicKey)));
      expect(id.sign.publicKey, hasLength(32));
      expect(id.box.publicKey, hasLength(32));
    });

    test('rejects wrong entropy length', () {
      expect(() => PorchIdentity.fromEntropy(sodium, Uint8List(15)),
          throwsArgumentError);
    });

    test('generate() mints 16 fresh entropy bytes', () {
      final a = PorchIdentity.generate(sodium);
      final b = PorchIdentity.generate(sodium);
      expect(a.entropy, hasLength(16));
      expect(a.entropy, isNot(equals(b.entropy)));
    });

    test('mnemonic round-trip restores the identical identity', () {
      final original = PorchIdentity.generate(sodium);
      final words = entropyToMnemonic(original.entropy);
      final restored =
          PorchIdentity.fromEntropy(sodium, mnemonicToEntropy(words));
      expect(restored.sign.publicKey, original.sign.publicKey);
      expect(restored.box.publicKey, original.box.publicKey);
      expect(restored.mailboxId, original.mailboxId);
    });

    test('identity signs and peers verify with the public key', () {
      final id = PorchIdentity.fromEntropy(sodium, entropyOf(7));
      final msg = Uint8List.fromList('porch says hi'.codeUnits);
      final sig = sodium.crypto.sign
          .detached(message: msg, secretKey: id.sign.secretKey);
      expect(
          sodium.crypto.sign.verifyDetached(
              message: msg, signature: sig, publicKey: id.sign.publicKey),
          isTrue);
    });
  });

  group('deriveMailboxId', () {
    // Cross-language pin: the Go relay's sigauth_test.go asserts this exact
    // vector (pk = 0x00..0x1f), itself pinned against Python hashlib.blake2b.
    // Three independent implementations must agree on these bytes.
    test('matches the relay-pinned vector for pk 0x00..0x1f', () {
      final pk = Uint8List.fromList(List.generate(32, (i) => i));
      expect(deriveMailboxId(sodium, pk),
          '587EjM9iNfVFa_VYVllvCcsFWqNZr3zGndg-SN3HPg8');
    });

    test('is base64url-no-padding of 32 hash bytes (43 chars)', () {
      final id = PorchIdentity.fromEntropy(sodium, entropyOf(3));
      expect(id.mailboxId, hasLength(43));
      expect(b64urlNoPadDecode(id.mailboxId), hasLength(32));
    });
  });

  group('backup blob (§3.1 step 7)', () {
    // Interactive limits keep the suite fast; the params ride in the header
    // so restore never guesses. A separate test pins the production default
    // to MODERATE.
    late int fastOps;
    late int fastMem;
    setUpAll(() {
      fastOps = sodium.crypto.pwhash.opsLimitInteractive;
      fastMem = sodium.crypto.pwhash.memLimitInteractive;
    });

    Uint8List seal(Uint8List entropy, Map<String, Object?> state) =>
        sealBackup(sodium,
            entropy: entropy,
            stateSnapshot: state,
            opsLimit: fastOps,
            memLimit: fastMem);

    String wordsFor(Uint8List entropy) =>
        backupPassphrase(sodium, entropy).join(' ');

    test('seal → open with the 6 backup words round-trips entropy and '
        'state snapshot', () {
      final entropy = entropyOf(0x5a);
      final state = {
        'groups': [
          {'groupUuid': 'g-1', 'epoch': 3},
        ],
      };
      final blob = seal(entropy, state);
      final restored =
          openBackup(sodium, passphrase: wordsFor(entropy), blob: blob);
      expect(restored.entropy, entropy);
      expect(restored.stateSnapshot, state);
    });

    test('the passphrase is 6 words from the same list as the 12 words, '
        'fixed by the identity and different for another identity', () {
      final words = backupPassphrase(sodium, entropyOf(0x5a));
      expect(words, hasLength(6));
      for (final w in words) {
        expect(bip39English, contains(w));
      }
      expect(backupPassphrase(sodium, entropyOf(0x5a)), words);
      expect(backupPassphrase(sodium, entropyOf(0x5b)), isNot(words));
      // Not the start of the 12 words: knowing one says nothing of the other.
      expect(entropyToMnemonic(entropyOf(0x5a)).take(6), isNot(words));
    });

    test('restore tolerates case and spaces in the 6 words', () {
      final entropy = entropyOf(0x31);
      final blob = seal(entropy, const {});
      final messy =
          '  ${backupPassphrase(sodium, entropy).map((w) => w.toUpperCase()).join('   ')}\n';
      expect(openBackup(sodium, passphrase: messy, blob: blob).entropy,
          entropy);
    });

    test('a 4-digit PIN, or anything but 6 list words, is refused before '
        'any key is derived', () {
      final entropy = entropyOf(0x22);
      final blob = seal(entropy, const {});
      final five = backupPassphrase(sodium, entropy).take(5).join(' ');
      for (final bad in ['1234', '482913', '', five, '$five notaword']) {
        expect(
            () => openBackup(sodium, passphrase: bad, blob: blob),
            throwsA(isA<BackupException>().having(
                (e) => e.message, 'message', 'not 6 backup words')),
            reason: bad);
      }
    });

    test('wrong words fail cleanly with BackupException', () {
      final blob = seal(entropyOf(1), const {});
      expect(
          () => openBackup(sodium,
              passphrase: wordsFor(entropyOf(2)), blob: blob),
          throwsA(isA<BackupException>()));
    });

    test('corrupted blob fails cleanly with BackupException', () {
      final blob = seal(entropyOf(1), const {});
      final words = wordsFor(entropyOf(1));
      final tampered = Uint8List.fromList(blob);
      tampered[tampered.length - 10] ^= 0xff;
      expect(() => openBackup(sodium, passphrase: words, blob: tampered),
          throwsA(isA<BackupException>()));
      expect(
          () => openBackup(sodium,
              passphrase: words, blob: Uint8List.fromList([1, 2, 3])),
          throwsA(isA<BackupException>()));
    });

    group('a crafted header cannot hang or crash restore', () {
      Uint8List withHeader(Uint8List blob, Map<String, Object?> change) {
        final header =
            (jsonDecode(utf8.decode(blob)) as Map).cast<String, Object?>();
        header.addAll(change);
        return Uint8List.fromList(utf8.encode(jsonEncode(header)));
      }

      final cases = <String, Map<String, Object?> Function(SodiumSumo)>{
        'mem above SENSITIVE': (s) =>
            {'mem': s.crypto.pwhash.memLimitSensitive + 1},
        'absurd mem (1 TiB)': (_) => {'mem': 1 << 40},
        'ops above SENSITIVE': (s) =>
            {'ops': s.crypto.pwhash.opsLimitSensitive + 1},
        'absurd ops': (_) => {'ops': 1 << 40},
        'mem below the minimum': (_) => {'mem': 0},
        'ops below the minimum': (_) => {'ops': 0},
      };
      for (final c in cases.entries) {
        test('${c.key} is refused', () {
          final entropy = entropyOf(4);
          final blob = withHeader(seal(entropy, const {}), c.value(sodium));
          expect(
              () => openBackup(sodium,
                  passphrase: wordsFor(entropy), blob: blob),
              throwsA(isA<BackupException>().having((e) => e.message,
                  'message', 'backup parameters out of range')));
        });
      }

      test('the minimum is accepted: past the header, the AEAD decides',
          () {
        // The upper bound cannot be shown accepted here: SENSITIVE asks
        // Argon2id for 1 GiB. The bounds are inclusive in the code.
        final entropy = entropyOf(4);
        final blob = withHeader(seal(entropy, const {}), {
          'ops': sodium.crypto.pwhash.opsLimitMin,
          'mem': sodium.crypto.pwhash.memLimitMin,
        });
        expect(
            () => openBackup(sodium,
                passphrase: wordsFor(entropy), blob: blob),
            throwsA(isA<BackupException>().having((e) => e.message,
                'message', 'wrong words or corrupted backup')));
      });
    });

    test('two seals of the same content differ (fresh salt + nonce)', () {
      final blob1 = seal(entropyOf(2), const {});
      final blob2 = seal(entropyOf(2), const {});
      expect(blob1, isNot(equals(blob2)));
    });

    test('default parameters are Argon2id MODERATE (spec §3.1)', () {
      expect(defaultBackupOpsLimit(sodium),
          sodium.crypto.pwhash.opsLimitModerate);
      expect(defaultBackupMemLimit(sodium),
          sodium.crypto.pwhash.memLimitModerate);
    });
  });
}
