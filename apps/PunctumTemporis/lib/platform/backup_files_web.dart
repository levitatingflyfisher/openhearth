import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'file_storage_web.dart';

/// One file to pack. On web every entry is read into memory first, as the
/// web build always has: the browser gives no file handle to stream from.
class BackupEntry {
  const BackupEntry.file(this.name, String this.sourcePath) : bytes = null;
  const BackupEntry.bytes(this.name, Uint8List this.bytes) : sourcePath = null;

  final String name;
  final String? sourcePath;
  final Uint8List? bytes;
}

/// Never made on web: [BackupFiles.streams] is false, so the backup
/// service takes its in-memory path and never opens a ZIP by path.
class OpenZip {
  OpenZip._();
  Archive get archive => throw UnsupportedError('No ZIP files on web');
  Future<void> close() async {}
}

/// The web twin. Only [writeEntry] is used: create and restore work on
/// bytes in memory, the browser's download and picker hand over bytes.
abstract final class BackupFiles {
  static const streams = false;

  static Future<void> writeZip(String path, List<BackupEntry> entries,
          void Function(int done) onEntry) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<OpenZip> openZip(String path) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<void> writeEntry(ArchiveFile entry, String destPath) =>
      FileStorage.writeBytes(
          destPath, Uint8List.fromList(entry.content as List<int>));

  static Stream<List<int>> openRead(String path) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<void> writeStream(String path, Stream<List<int>> data) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<List<int>> readHead(String path, int count) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<int> length(String path) =>
      throw UnsupportedError('Streamed backups are native only');

  static Future<void> delete(String path) => FileStorage.deleteFile(path);

  static Future<void> rename(String from, String to) =>
      FileStorage.moveFile(from, to);
}
