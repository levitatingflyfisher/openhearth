// state_store — one encrypted, versioned state blob (BUILD-SPEC §1.5
// client-storage row, §5.2).
//
// Blob format (state.v1.enc on device):
//   nonce(24) ‖ crypto_aead_xchacha20poly1305_ietf_encrypt(
//     key = 32 B state key (Keystore-held, key_store.dart),
//     ad  = utf8("porch/state/v1"),
//     msg = utf8(JSON document with a top-level "v"))
//
// The version lives INSIDE the ciphertext: an attacker with the blob learns
// its size and nothing else, not even the schema version.
//
// The crypto + versioning ([EncryptedStateStore]) is platform-free and rides a
// [StateBlobStore] seam for the raw bytes: on device that is an atomically
// written file (state_store_native.dart); on web it is a base64 value in
// browser storage (state_store_web.dart) — a real durability/security downgrade
// the web-preview notice owns. The conditional export below hands bootstrap the
// right one; tests reach the native [EncryptedFileStateStore] through it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../domain/domain.dart' show concatBytes;
import 'porch_state.dart';

export 'state_store_native.dart'
    if (dart.library.js_interop) 'state_store_web.dart';

const stateAd = 'porch/state/v1';

/// The blob exists but cannot be decrypted or parsed — wrong key, tampering,
/// or storage corruption. Callers surface this loudly; silently starting fresh
/// would orphan every group key the user holds.
class StateCorruptError extends Error {
  final String message;
  StateCorruptError(this.message);
  @override
  String toString() => 'StateCorruptError: $message';
}

/// The document decrypted fine but carries an unknown version and no
/// migrator was provided (a newer app wrote it, then the user downgraded).
class StateVersionError extends Error {
  final int found;
  StateVersionError(this.found);
  @override
  String toString() =>
      'StateVersionError: document v$found, expected v${PorchState.version}';
}

abstract interface class StateStore {
  /// The persisted state, or null on a fresh install.
  Future<PorchState?> load();

  Future<void> save(PorchState state);

  /// Remove the stored state, so the next [load] is null as on a fresh
  /// install. Start over uses it before the keys go: a state file left
  /// behind would meet the next launch's new state key and read as corrupt.
  Future<void> clear();
}

/// The raw single-blob persistence under [EncryptedStateStore]. One named blob
/// (nonce ‖ ciphertext); [read] also disposes of crash residue (a native
/// interrupted-write temp file). Platform impls live in the *_native / *_web
/// files.
abstract interface class StateBlobStore {
  /// The stored blob, or null if none has ever been written.
  Future<Uint8List?> read();

  /// Atomically replace the stored blob with [bytes].
  Future<void> write(Uint8List bytes);

  /// Remove the stored blob and any crash residue. No blob: no error.
  Future<void> clear();
}

/// The platform-free encrypted state store: XChaCha20-Poly1305 over a
/// [StateBlobStore]. This is the single home of the crypto and version logic,
/// so both the file-backed device store and the browser-backed web store share
/// it exactly (and it is host-VM testable against any fake [StateBlobStore]).
class EncryptedStateStore implements StateStore {
  final Sodium _sodium;
  final StateBlobStore _blobs;
  final Uint8List _stateKey;

  /// Version migration hook: receives the decrypted document whenever its
  /// "v" != [PorchState.version] and must return a v1-shaped document.
  final Map<String, Object?> Function(Map<String, Object?> json)? migrate;

  EncryptedStateStore(
    this._sodium, {
    required StateBlobStore blobs,
    required Uint8List stateKey,
    this.migrate,
  })  : _blobs = blobs,
        _stateKey = Uint8List.fromList(stateKey) {
    if (stateKey.length != 32) {
      throw ArgumentError.value(
          stateKey.length, 'stateKey', 'must be exactly 32 bytes');
    }
  }

  @override
  Future<PorchState?> load() async {
    final bytes = await _blobs.read();
    if (bytes == null) return null;

    final nonceLen = _sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes;
    if (bytes.length <= nonceLen) {
      throw StateCorruptError('state blob too short (${bytes.length} B)');
    }
    final key = SecureKey.fromList(_sodium, _stateKey);
    final Uint8List plain;
    try {
      plain = _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: Uint8List.sublistView(bytes, nonceLen),
        nonce: Uint8List.sublistView(bytes, 0, nonceLen),
        key: key,
        additionalData: Uint8List.fromList(utf8.encode(stateAd)),
      );
    } on Object {
      throw StateCorruptError('decryption failed (wrong key or tampering)');
    } finally {
      key.dispose();
    }

    Map<String, Object?> doc;
    try {
      doc = (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
    } on Object {
      throw StateCorruptError('decrypted payload is not a JSON document');
    }
    if (doc['v'] != PorchState.version) {
      final m = migrate;
      if (m == null) {
        throw StateVersionError(doc['v'] is int ? doc['v'] as int : -1);
      }
      doc = m(doc);
      if (doc['v'] != PorchState.version) {
        throw StateVersionError(doc['v'] is int ? doc['v'] as int : -1);
      }
    }
    try {
      return PorchState.fromJson(doc);
    } on Object catch (e) {
      throw StateCorruptError('v1 document malformed: $e');
    }
  }

  @override
  Future<void> save(PorchState state) async {
    final nonce = _sodium.randombytes
        .buf(_sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes);
    final key = SecureKey.fromList(_sodium, _stateKey);
    final Uint8List ct;
    try {
      ct = _sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: Uint8List.fromList(utf8.encode(jsonEncode(state.toJson()))),
        nonce: nonce,
        key: key,
        additionalData: Uint8List.fromList(utf8.encode(stateAd)),
      );
    } finally {
      key.dispose();
    }
    await _blobs.write(concatBytes([nonce, ct]));
  }

  @override
  Future<void> clear() => _blobs.clear();
}

/// In-memory StateStore for repository tests. It round-trips through REAL
/// JSON on every save/load, so (a) non-serializable state fails the test
/// that created it and (b) loads are deep copies — mutations cannot leak
/// back without a save, exactly like a file.
class InMemoryStateStore implements StateStore {
  String? _doc;

  /// Number of saves — lets tests assert persistence actually happened.
  int saves = 0;

  @override
  Future<PorchState?> load() async {
    final doc = _doc;
    if (doc == null) return null;
    return PorchState.fromJson(
        (jsonDecode(doc) as Map).cast<String, Object?>());
  }

  @override
  Future<void> save(PorchState state) async {
    _doc = jsonEncode(state.toJson());
    saves++;
  }

  @override
  Future<void> clear() async => _doc = null;
}
