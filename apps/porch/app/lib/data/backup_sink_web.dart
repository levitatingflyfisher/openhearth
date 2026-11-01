// backup_sink_web — the browser backup sink, used only by `flutter build web`.
//
// The ciphertext blob is stored base64 in window.localStorage under a
// timestamped key (a fresh key per save, like the file sink's fresh name). The
// returned message is honest: this is browser storage in a preview, not a file
// the user can hand to a new phone. A real cross-device backup is the Android
// app's job — the web-preview notice says so.
import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'backup_sink.dart';

/// Bootstrap's platform-selected constructor (mirrors the native signature).
/// [directory], [excludeFromBackup] and [sharedCopiesRoot] are unused on
/// web: there is no filesystem path, and a shared copy is a download the
/// browser hands to the person.
BackupSink createBackupSink(
        {required String directory,
        ExcludeFromBackup? excludeFromBackup,
        String? sharedCopiesRoot}) =>
    LocalStorageBackupSink();

class LocalStorageBackupSink implements BackupSink {
  /// Injectable clock for deterministic keys in tests.
  final DateTime Function() now;

  LocalStorageBackupSink({DateTime Function()? now}) : now = now ?? DateTime.now;

  @override
  Future<String> save(Uint8List blob) async {
    final stamp = backupStamp(now());
    var key = 'porch.backup.$stamp';
    var n = 1;
    while (web.window.localStorage.getItem(key) != null) {
      key = 'porch.backup.$stamp-${n++}';
    }
    web.window.localStorage.setItem(key, base64.encode(blob));
    return 'saved to this browser\'s storage ($key). This is a preview — '
        'for a real, portable backup use the Android app.';
  }

  /// Every `porch.backup.*` value in this browser's storage. The keys are
  /// read first, then removed, so removing never skips one.
  @override
  Future<void> deleteAll() async {
    final storage = web.window.localStorage;
    final keys = [
      for (var i = 0; i < storage.length; i++) storage.key(i),
    ].whereType<String>().where((k) => k.startsWith('porch.backup.')).toList();
    for (final k in keys) {
      storage.removeItem(k);
    }
  }
}
