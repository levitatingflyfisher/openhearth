// key_store — the two device secrets (BUILD-SPEC §5.1) behind a tiny
// SecretStore abstraction.
//
//   porch.entropy.v1  → 16 B identity entropy (hex) — what the 12 words spell
//   porch.statekey.v1 → 32 B state-file encryption key (hex)
//
// A garbled identity can be set aside under a dated key before a restore
// (porch.entropy.v1.garbled-YYYY-MM-DD, listed in porch.setaside.v1); it is
// never deleted, except by leave-and-burn.
//
// Production binds SecretStore to flutter_secure_storage
// (secure_storage_adapter.dart → Android Keystore / iOS Keychain); tests use
// [InMemorySecretStore]. Nothing else in the app touches these keys — the
// encrypted state file holds everything non-secret-critical.
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show Sodium;

/// Minimal secret storage: string keys, string values, platform-secured.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Test fake. Also useful as an explicit "insecure" store for host-side
/// tooling — the name says what it is.
class InMemorySecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// A secret is stored but cannot be read as one: not hex, or the wrong
/// size. It is never treated as absent, because "absent" lets onboarding
/// write a new identity, or launch a new state key, over the stored one.
/// The message names the secret, never its value.
class CorruptSecretException implements Exception {
  final String key;
  const CorruptSecretException(this.key);

  @override
  String toString() =>
      'CorruptSecretException: the stored $key is not a valid secret';
}

/// Typed access to Porch's two secrets. All byte↔hex conversion and size
/// validation lives here so callers only ever see correctly-sized bytes.
class PorchKeyStore {
  static const entropyKey = 'porch.entropy.v1';
  static const stateKeyKey = 'porch.statekey.v1';

  final SecretStore _store;
  const PorchKeyStore(this._store);

  /// The 16-byte identity entropy, or null before onboarding. A stored
  /// value that is not 16 bytes of hex throws [CorruptSecretException].
  Future<Uint8List?> readEntropy() async =>
      _readSized(entropyKey, 16);

  Future<void> writeEntropy(Uint8List entropy) async {
    if (entropy.length != 16) {
      throw ArgumentError.value(
          entropy.length, 'entropy', 'must be exactly 16 bytes');
    }
    await _store.write(entropyKey, _hex(entropy));
  }

  /// The 32-byte state-file key, or null if never generated. A stored
  /// value that is not 32 bytes of hex throws [CorruptSecretException].
  Future<Uint8List?> readStateKey() async => _readSized(stateKeyKey, 32);

  /// Generate-once: returns the existing state key or mints, persists and
  /// returns a fresh random 32-byte key. Never rotates an existing key —
  /// rotating would orphan the state file — and never writes over a stored
  /// key it cannot read (that throws, from [readStateKey]).
  Future<Uint8List> ensureStateKey(Sodium sodium) async {
    final existing = await readStateKey();
    if (existing != null) return existing;
    final fresh = sodium.randombytes.buf(32);
    await _store.write(stateKeyKey, _hex(fresh));
    return fresh;
  }

  /// Where the set-aside names are listed, one per line.
  static const setAsideIndexKey = 'porch.setaside.v1';

  /// Moves a garbled stored identity aside, so a restore from the 12 words
  /// or a backup can write a new one without losing the old value for good
  /// (the publisher's rule, 14 Nov). The raw value is copied to
  /// `porch.entropy.v1.garbled-<UTC day>` (with `-2`, `-3` … when that name
  /// is taken), listed under [setAsideIndexKey], checked, and only then
  /// removed from [entropyKey]. Returns the new name, or null when nothing
  /// is stored. A readable identity is never set aside: that throws
  /// [StateError].
  Future<String?> setAsideCorruptEntropy(DateTime now) async {
    final raw = await _store.read(entropyKey);
    if (raw == null) return null;
    final bytes = _unhex(raw);
    if (bytes != null && bytes.length == 16) {
      throw StateError('the stored identity is readable; it is never set aside');
    }
    final utc = now.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${utc.year}-${two(utc.month)}-${two(utc.day)}';
    final base = '$entropyKey.garbled-$day';
    var name = base;
    for (var n = 2; await _store.read(name) != null; n++) {
      name = '$base-$n';
    }
    await _store.write(name, raw);
    await _store.write(
        setAsideIndexKey, [...await setAsideKeys(), name].join('\n'));
    if (await _store.read(name) != raw) {
      throw StateError('the set-aside copy did not read back; '
          'the stored identity was left in place');
    }
    await _store.delete(entropyKey);
    return name;
  }

  /// The names of every secret set aside on this phone, oldest first.
  Future<List<String>> setAsideKeys() async {
    final index = await _store.read(setAsideIndexKey);
    if (index == null || index.isEmpty) return const [];
    return index.split('\n');
  }

  /// Delete both secrets — the leave-and-burn path. The encrypted state
  /// file becomes permanently unreadable the moment the state key is gone.
  /// Set-aside copies go too: leaving burns every secret Porch holds.
  Future<void> wipe() async {
    await _store.delete(entropyKey);
    await _store.delete(stateKeyKey);
    for (final name in await setAsideKeys()) {
      await _store.delete(name);
    }
    await _store.delete(setAsideIndexKey);
  }

  Future<Uint8List?> _readSized(String key, int expectedBytes) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    final bytes = _unhex(raw);
    if (bytes == null || bytes.length != expectedBytes) {
      throw CorruptSecretException(key);
    }
    return bytes;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List? _unhex(String s) {
    if (s.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(s)) return null;
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
