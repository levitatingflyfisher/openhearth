import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Native (Android) file storage — thin wrappers around dart:io + path_provider.
/// All paths are real filesystem paths.
class FileStorage {
  // ── Directories ────────────────────────────────────────────────────────────

  static Future<String> appDocDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<String?> externalStorageDir() async {
    try {
      final dir = await getExternalStorageDirectory();
      return dir?.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> ensureDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  // ── Existence ───────────────────────────────────────────────────────────────

  static Future<bool> exists(String path) async {
    return File(path).exists();
  }

  static Future<bool> dirExists(String path) async {
    return Directory(path).exists();
  }

  static bool existsSync(String path) {
    return File(path).existsSync();
  }

  // ── Read ────────────────────────────────────────────────────────────────────

  static Future<Uint8List?> readBytes(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  static Future<String?> readString(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  // ── Write ───────────────────────────────────────────────────────────────────

  static Future<void> writeBytes(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes);
  }

  static int _tempWrites = 0;

  /// Replaces [path] whole or not at all. A plain write truncates first, so
  /// a kill or a full disk partway through would damage metadata.json, the
  /// only record of which clip belongs to which day. The new content goes to
  /// a temporary file in the same folder and reaches the disk before the
  /// rename, which swaps it in as one step.
  static Future<void> writeString(String path, String content) async {
    // Unique per write, so two overlapping saves never share a file. Only a
    // kill in the short gap before the rename can leave one behind.
    final temp = File('$path.$pid.${_tempWrites++}.tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // The write's own failure is the one worth reporting.
      }
      rethrow;
    }
  }

  // ── Delete / Copy ───────────────────────────────────────────────────────────

  static Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  static Future<void> copyFile(String sourcePath, String destPath) async {
    await File(sourcePath).copy(destPath);
  }

  /// Moves a file within one folder. A rename needs no free space, so it
  /// still works on the full disk that may have broken the file.
  static Future<void> moveFile(String sourcePath, String destPath) async {
    await File(sourcePath).rename(destPath);
  }

  // ── Web-only helpers (no-op on native) ─────────────────────────────────────

  /// Triggers a browser download of bytes. No-op on native (file is written to path instead).
  static Future<void> downloadFile(
      Uint8List bytes, String filename, String mimeType) async {
    // On native, caller should use share_plus or save to external storage directly.
    // This method is a no-op; callers check kIsWeb before calling.
  }

  /// Creates an object URL for in-memory bytes (for video playback).
  /// Returns null on native — use file:// path directly.
  static String? createObjectUrl(Uint8List bytes, String mimeType) => null;

  /// Revokes an object URL previously created by [createObjectUrl]. No-op on native.
  static void revokeObjectUrl(String url) {}
}
