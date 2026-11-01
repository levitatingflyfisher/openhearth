import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// One file to pack: either a file on disk ([sourcePath]) read in pieces,
/// or small bytes already in memory ([bytes]: metadata.json, settings.json).
class BackupEntry {
  const BackupEntry.file(this.name, String this.sourcePath) : bytes = null;
  const BackupEntry.bytes(this.name, Uint8List this.bytes) : sourcePath = null;

  final String name;
  final String? sourcePath;
  final Uint8List? bytes;
}

/// A ZIP opened from disk. Its directory is in memory; entry contents are
/// read from the file only when asked for. Close it when done.
class OpenZip {
  OpenZip._(this.archive, this._input);
  final Archive archive;
  final InputFileStream _input;
  Future<void> close() => _input.close();
}

/// Backup files on Android: every step reads and writes in pieces, so a
/// library of many gigabytes needs no more memory than a small one.
abstract final class BackupFiles {
  /// True here: create and restore go file to file.
  static const streams = true;

  /// Writes a ZIP at [path] without holding any clip in memory. Video and
  /// pictures are stored as they are (they are compressed already, and
  /// deflating them in Dart would cost minutes for nothing); the JSON
  /// entries are deflated.
  static Future<void> writeZip(
    String path,
    List<BackupEntry> entries,
    void Function(int done) onEntry,
  ) async {
    final encoder = ZipFileEncoder()..create(path, level: ZipFileEncoder.store);
    try {
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final source = entry.sourcePath;
        if (source != null) {
          await encoder.addFile(File(source), entry.name, ZipFileEncoder.store);
        } else {
          final bytes = entry.bytes!;
          encoder.addArchiveFile(ArchiveFile(entry.name, bytes.length, bytes)
            ..compression = CompressionType.deflate);
        }
        onEntry(i + 1);
      }
    } finally {
      await encoder.close();
    }
  }

  /// Opens the ZIP at [path] for reading.
  static Future<OpenZip> openZip(String path) async {
    final input = InputFileStream(path);
    try {
      return OpenZip._(ZipDecoder().decodeStream(input), input);
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  /// Writes one entry's content to [destPath], in pieces.
  static Future<void> writeEntry(ArchiveFile entry, String destPath) async {
    final out = OutputFileStream(destPath);
    try {
      entry.writeContent(out);
    } finally {
      await out.close();
    }
  }

  static Stream<List<int>> openRead(String path) => File(path).openRead();

  /// Writes [data] to [path], one piece at a time: the next piece is not
  /// asked for until the last is on disk, so a fast producer cannot pile
  /// chunks up in memory. A failing source (wrong words, a cut file) ends
  /// the write with its own error; an IOSink would close itself on that
  /// error and then hide it behind "File closed".
  static Future<void> writeStream(String path, Stream<List<int>> data) async {
    final file = await File(path).open(mode: FileMode.write);
    try {
      await for (final piece in data) {
        await file.writeFrom(piece);
      }
    } finally {
      await file.close();
    }
  }

  /// The first [count] bytes of [path] (fewer if the file is shorter).
  static Future<List<int>> readHead(String path, int count) async {
    final file = await File(path).open();
    try {
      return await file.read(count);
    } finally {
      await file.close();
    }
  }

  static Future<int> length(String path) => File(path).length();

  static Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  static Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }
}
