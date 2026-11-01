// state_store_web — the browser state blob store, used only by
// `flutter build web`.
//
// The same [EncryptedStateStore] crypto runs; only the bytes land differently:
// base64 in window.localStorage instead of an atomic file. This is a real
// downgrade the web-preview notice owns: localStorage is not encrypted at rest
// by the OS, has no atomic-rename crash safety, and the browser can evict it.
// It is acceptable for a preview whose keys the user is told not to trust.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show Sodium;
import 'package:web/web.dart' as web;

import 'state_store.dart';

const _stateStorageKey = 'porch.state.v1';

/// Bootstrap's platform-selected constructor (mirrors the native signature).
/// [directory] is unused on web — there is no filesystem path.
StateStore createPersistentStateStore(
  Sodium sodium, {
  required String directory,
  required Uint8List stateKey,
  Map<String, Object?> Function(Map<String, Object?>)? migrate,
}) =>
    EncryptedStateStore(sodium,
        blobs: LocalStorageStateBlobStore(_stateStorageKey),
        stateKey: stateKey,
        migrate: migrate);

/// The whole encrypted state blob as one base64 localStorage value.
class LocalStorageStateBlobStore implements StateBlobStore {
  final String key;
  LocalStorageStateBlobStore(this.key);

  @override
  Future<Uint8List?> read() async {
    final v = web.window.localStorage.getItem(key);
    if (v == null || v.isEmpty) return null;
    try {
      return base64.decode(v);
    } on FormatException {
      // A garbled value reads as "corrupt blob"; EncryptedStateStore surfaces
      // it as StateCorruptError rather than silently starting fresh.
      return Uint8List.fromList(const [0]);
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    web.window.localStorage.setItem(key, base64.encode(bytes));
  }

  @override
  Future<void> clear() async => web.window.localStorage.removeItem(key);
}
