// state_store_native — the device (dart:io) state blob store.
//
// Atomicity: [write] writes state.v1.enc.tmp, flushes, then renames over the
// real file — a kill mid-write leaves the previous state intact (POSIX rename
// semantics). [read] ignores and removes stray tmp files (crash residue from
// an interrupted save: the real file is authoritative, the fragment is
// meaningless ciphertext).
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show Sodium;

import 'state_store.dart';

const _stateFileName = 'state.v1.enc';

/// Bootstrap's platform-selected constructor (mirrored on web). Returns the
/// device store: an [EncryptedStateStore] over a file in [directory].
StateStore createPersistentStateStore(
  Sodium sodium, {
  required String directory,
  required Uint8List stateKey,
  Map<String, Object?> Function(Map<String, Object?>)? migrate,
}) =>
    EncryptedFileStateStore(sodium,
        directory: directory, stateKey: stateKey, migrate: migrate);

/// The atomic file blob store. [read] first clears any interrupted-write temp.
class FileStateBlobStore implements StateBlobStore {
  final String directory;
  FileStateBlobStore(this.directory);

  File get _file => File('$directory/$_stateFileName');
  File get _tmp => File('$directory/$_stateFileName.tmp');

  @override
  Future<Uint8List?> read() async {
    if (await _tmp.exists()) await _tmp.delete();
    if (!await _file.exists()) return null;
    return _file.readAsBytes();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    await _tmp.writeAsBytes(bytes, flush: true);
    await _tmp.rename(_file.path); // atomic on POSIX
  }

  @override
  Future<void> clear() async {
    if (await _tmp.exists()) await _tmp.delete();
    if (await _file.exists()) await _file.delete();
  }
}

/// The device state store, unchanged in name and constructor for the W3 test
/// suite and bootstrap: file-backed [EncryptedStateStore].
class EncryptedFileStateStore extends EncryptedStateStore {
  EncryptedFileStateStore(
    super.sodium, {
    required String directory,
    required super.stateKey,
    super.migrate,
  }) : super(blobs: FileStateBlobStore(directory));
}
