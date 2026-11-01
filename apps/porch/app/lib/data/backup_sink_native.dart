// backup_sink_native — the device (dart:io) backup sink: a file in a folder
// no automatic backup takes (see backup_sink.dart), made on first save. A
// fresh name per save means a second backup never clobbers the first.
import 'dart:io';
import 'dart:typed_data';

import 'backup_sink.dart';

/// Bootstrap's platform-selected constructor (mirrored on web).
/// [sharedCopiesRoot] is the app's temporary folder, where the share sheet
/// is handed its copy of a backup file.
BackupSink createBackupSink(
        {required String directory,
        ExcludeFromBackup? excludeFromBackup,
        String? sharedCopiesRoot}) =>
    FileBackupSink(
        directory: directory,
        excludeFromBackup: excludeFromBackup,
        sharedCopiesRoot: sharedCopiesRoot);

/// A backup file's name, as [FileBackupSink.save] and the share sheet
/// (PorchActions.shareBackup, the move page) both name it.
final _backupFileName = RegExp(r'^porch-.*\.porchbackup$');

class FileBackupSink implements BackupSink {
  final String directory;

  /// Injectable clock for deterministic file names in tests.
  final DateTime Function() now;

  /// Called on the folder before every write; a failure stops the write.
  final ExcludeFromBackup? excludeFromBackup;

  /// Where the share sheet's copies land: share_plus writes each one as
  /// `<this>/<random folder>/<file name>` and leaves it there.
  final String? sharedCopiesRoot;

  FileBackupSink(
      {required this.directory,
      DateTime Function()? now,
      this.excludeFromBackup,
      this.sharedCopiesRoot})
      : now = now ?? DateTime.now;

  @override
  Future<String> save(Uint8List blob) async {
    await Directory(directory).create(recursive: true);
    // Before every write, not once: the flag must hold for this file even
    // if the folder was made again since the last save.
    await excludeFromBackup?.call(directory);
    final stamp = backupStamp(now());
    var file = File('$directory/porch-$stamp.porchbackup');
    var n = 1;
    while (await file.exists()) {
      file = File('$directory/porch-$stamp-${n++}.porchbackup');
    }
    await file.writeAsBytes(blob, flush: true);
    return file.path;
  }

  /// The backups folder is Porch's own, so it goes whole. Under the shared
  /// copies folder only backup files go, each with its random folder once
  /// that holds nothing else.
  @override
  Future<void> deleteAll() async {
    final own = Directory(directory);
    if (await own.exists()) await own.delete(recursive: true);
    final root = sharedCopiesRoot;
    if (root == null) return;
    final shared = Directory(root);
    if (!await shared.exists()) return;
    await for (final sub in shared.list(followLinks: false)) {
      if (sub is! Directory) continue;
      var deleted = false;
      await for (final f in sub.list(followLinks: false)) {
        if (f is File && _backupFileName.hasMatch(_baseName(f.path))) {
          await f.delete();
          deleted = true;
        }
      }
      if (deleted && await sub.list().isEmpty) await sub.delete();
    }
  }

  static String _baseName(String path) =>
      path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
}
