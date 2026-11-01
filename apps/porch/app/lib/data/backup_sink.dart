// backup_sink — where the encrypted backup blob (§3.1 step 7) is
// written. Sinks receive ciphertext only (sealBackup already ran); they
// move bytes and report, honestly, where those bytes went.
//
// On device [FileBackupSink] writes to a `backups` folder that no automatic
// backup takes: the file should leave the phone only when the person
// shares it. Every platform keeps it under the app support folder, which
// the system never clears to free space. Android (files/): the backup
// rules exclude the `backups` folder by name. iOS and macOS: the folder is
// marked excluded from backup before each file is written
// ([ExcludeFromBackup], lib/backup_folder_adapter.dart), and a file is
// never written if that fails. On web the blob lands in browser storage
// (state_store_web.dart's neighbour), a preview convenience only.
// "User-chosen cloud/file storage" via a system picker is a future adapter
// behind this same port; HONEST-STATUS records that gap.
//
// The core here is platform-free (the interface + the test double); the
// conditional export hands bootstrap the right sink and re-exposes the native
// [FileBackupSink] to the W4 test suite.
import 'dart:typed_data';

export 'backup_sink_native.dart'
    if (dart.library.js_interop) 'backup_sink_web.dart';

/// The folder, under the app support folder, that holds backup files. The
/// Android backup rules exclude it by this name.
const backupFolderName = 'backups';

/// Marks [directory] as excluded from automatic backup, or throws. Needed
/// where no rules file of the app's own does it (iOS and macOS).
typedef ExcludeFromBackup = Future<void> Function(String directory);

abstract interface class BackupSink {
  /// Persist [blob]; returns a human-readable description of where it went
  /// (shown to the user verbatim).
  Future<String> save(Uint8List blob);

  /// Delete every backup file this phone holds: the ones [save] wrote, and
  /// the copies the system share sheet was handed. Start over runs it
  /// before the keys go. A file the person moved out of the app (into
  /// their files, another device) is out of reach, and the screen says so.
  Future<void> deleteAll();
}

/// Test double: captures every saved blob.
class RecordingBackupSink implements BackupSink {
  final saved = <Uint8List>[];
  @override
  Future<String> save(Uint8List blob) async {
    saved.add(Uint8List.fromList(blob));
    return 'recorded in memory (test sink)';
  }

  @override
  Future<void> deleteAll() async => saved.clear();
}

/// Shared UTC filename stamp (YYYYMMDD-HHMMSS) used by every sink so the
/// timestamping is identical across platforms and deterministic in tests.
String backupStamp(DateTime now) {
  final t = now.toUtc();
  return '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}'
      '${t.second.toString().padLeft(2, '0')}';
}
