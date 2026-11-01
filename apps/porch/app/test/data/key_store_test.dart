// W3-data: key_store — the two secrets of §5.1 behind a SecretStore
// abstraction (Keystore/Keychain in production, in-memory in tests).
//
//   porch.entropy.v1  → 16 B identity entropy (hex)
//   porch.statekey.v1 → 32 B state-file encryption key (hex)
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/key_store.dart';

import '../domain/support/test_sodium.dart';

void main() {
  late InMemorySecretStore secrets;
  late PorchKeyStore keys;

  setUp(() {
    secrets = InMemorySecretStore();
    keys = PorchKeyStore(secrets);
  });

  test('fresh install: both secrets absent', () async {
    expect(await keys.readEntropy(), isNull);
    expect(await keys.readStateKey(), isNull);
  });

  test('entropy round-trips as 16 bytes, stored hex under porch.entropy.v1',
      () async {
    final entropy = Uint8List.fromList(List.generate(16, (i) => i * 3 & 0xff));
    await keys.writeEntropy(entropy);
    expect(await keys.readEntropy(), entropy);
    final raw = await secrets.read('porch.entropy.v1');
    expect(raw, hasLength(32)); // 16 bytes hex
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(raw!), isTrue);
  });

  test('entropy of the wrong size is refused before it can be stored',
      () async {
    await expectLater(
        keys.writeEntropy(Uint8List(15)), throwsA(isA<ArgumentError>()));
    expect(await secrets.read('porch.entropy.v1'), isNull);
  });

  test('ensureStateKey generates 32 bytes ONCE and is stable thereafter',
      () async {
    final sodium = await loadTestSodium();
    final k1 = await keys.ensureStateKey(sodium);
    final k2 = await keys.ensureStateKey(sodium);
    expect(k1, hasLength(32));
    expect(k2, k1, reason: 'a second ensure must not rotate the key');
    expect(await keys.readStateKey(), k1);
  });

  // A stored secret that is present but unreadable is not "absent". Read
  // as absent, onboarding would write a new identity over the old one and
  // ensureStateKey would mint a new key over the one that opens the state
  // file: both secrets lost for good. So it is an error the app shows, and
  // nothing is written over it.
  group('a stored secret that is present but garbled', () {
    for (final (what, raw) in [
      ('not hex', 'not-hex-at-all'),
      ('odd length', 'abc'),
      ('the wrong size', 'abcd'),
    ]) {
      test('entropy ($what) throws CorruptSecretException', () async {
        await secrets.write('porch.entropy.v1', raw);
        await expectLater(
            keys.readEntropy(), throwsA(isA<CorruptSecretException>()));
        expect(await secrets.read('porch.entropy.v1'), raw);
      });

      test('state key ($what): ensureStateKey throws and keeps the stored '
          'value', () async {
        final sodium = await loadTestSodium();
        await secrets.write('porch.statekey.v1', raw);
        await expectLater(keys.ensureStateKey(sodium),
            throwsA(isA<CorruptSecretException>()));
        expect(await secrets.read('porch.statekey.v1'), raw,
            reason: 'no fresh key over the one that opens the state file');
      });
    }

    test('the error names the secret, never its value', () async {
      await secrets.write('porch.entropy.v1', 'zz' * 16);
      final error = await keys
          .readEntropy()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<CorruptSecretException>());
      expect(error.toString(), contains('porch.entropy.v1'));
      expect(error.toString(), isNot(contains('zz')));
    });
  });

  // The publisher's rule (14 Nov): a phone whose identity is garbled can restore
  // from its words or a backup, but the garbled value is moved aside under
  // a dated key first, never deleted.
  group('setting a garbled identity aside', () {
    final day = DateTime.utc(2026, 11, 14, 9, 30);

    test('moves the raw value to a dated key, then the identity reads as '
        'absent', () async {
      await secrets.write('porch.entropy.v1', 'not-hex-at-all');
      final name = await keys.setAsideCorruptEntropy(day);
      expect(name, 'porch.entropy.v1.garbled-2026-11-14');
      expect(await secrets.read(name!), 'not-hex-at-all');
      expect(await secrets.read('porch.entropy.v1'), isNull);
      expect(await keys.readEntropy(), isNull);
      expect(await keys.setAsideKeys(), [name]);
    });

    test('a second one on the same day never overwrites the first', () async {
      await secrets.write('porch.entropy.v1', 'first');
      final a = await keys.setAsideCorruptEntropy(day);
      await secrets.write('porch.entropy.v1', 'second');
      final b = await keys.setAsideCorruptEntropy(day);
      expect(b, isNot(a));
      expect(await secrets.read(a!), 'first');
      expect(await secrets.read(b!), 'second');
      expect(await keys.setAsideKeys(), [a, b]);
    });

    test('a readable identity is never set aside', () async {
      final entropy = Uint8List.fromList(List.generate(16, (i) => i));
      await keys.writeEntropy(entropy);
      await expectLater(
          keys.setAsideCorruptEntropy(day), throwsA(isA<StateError>()));
      expect(await keys.readEntropy(), entropy);
      expect(await keys.setAsideKeys(), isEmpty);
    });

    test('nothing stored: nothing to set aside', () async {
      expect(await keys.setAsideCorruptEntropy(day), isNull);
      expect(await keys.setAsideKeys(), isEmpty);
    });

    test('leave-and-burn removes the set-aside copies too', () async {
      await secrets.write('porch.entropy.v1', 'not-hex-at-all');
      final name = await keys.setAsideCorruptEntropy(day);
      await keys.wipe();
      expect(await secrets.read(name!), isNull);
      expect(await keys.setAsideKeys(), isEmpty);
    });
  });

  test('wipe removes both secrets (leave-and-burn path)', () async {
    final sodium = await loadTestSodium();
    await keys.writeEntropy(Uint8List(16));
    await keys.ensureStateKey(sodium);
    await keys.wipe();
    expect(await keys.readEntropy(), isNull);
    expect(await keys.readStateKey(), isNull);
  });
}
