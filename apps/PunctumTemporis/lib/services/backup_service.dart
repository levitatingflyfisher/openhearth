import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart'
    show BackupVault, VaultLabel;
import 'package:shared_preferences/shared_preferences.dart';
import '../platform/backup_files.dart';
import '../platform/file_storage.dart';
import '../utils/person_name.dart';
import 'backup_stream_cipher.dart';
import 'snapshot_serializer.dart';
import 'storage_service.dart';

class BackupInfo {
  /// Clip entries the archive's metadata.json DECLARES.
  final int clipCount;

  /// `.mp4` files actually PRESENT in the archive — the honest number for
  /// a "backed up and verified" receipt (metadata can reference clips
  /// whose video files were missing at pack time).
  final int clipFileCount;

  final String? dateRange; // "2025-01-01 to 2026-02-12"
  final int sizeBytes;
  final int compilationCount;
  final int faceCount;

  /// Montage `.mp4` files actually PRESENT under `compilations/` — the
  /// honest counterpart to [compilationCount], which only counts declared
  /// metadata rows (legacy archives, and montages whose file was already
  /// unreadable at pack time, declare rows they don't carry).
  final int montageFileCount;

  /// Whether the archive carries a `settings.json` entry. Legacy v1
  /// archives never do — a replace-mode restore of one leaves current
  /// settings untouched, and the confirmation copy must say so.
  final bool hasSettings;

  /// Whether the file is sealed with the recovery words (OHBS), rather
  /// than a plain ZIP.
  final bool encrypted;

  BackupInfo({
    required this.clipCount,
    this.clipFileCount = 0,
    this.dateRange,
    required this.sizeBytes,
    this.compilationCount = 0,
    this.faceCount = 0,
    this.montageFileCount = 0,
    this.hasSettings = false,
    this.encrypted = false,
  });

  BackupInfo _asFile(int size, {required bool encrypted}) => BackupInfo(
        clipCount: clipCount,
        clipFileCount: clipFileCount,
        dateRange: dateRange,
        sizeBytes: size,
        compilationCount: compilationCount,
        faceCount: faceCount,
        montageFileCount: montageFileCount,
        hasSettings: hasSettings,
        encrypted: encrypted,
      );
}

/// Thrown when a backup is sealed with recovery words and none were given.
/// The screen asks for the words and tries again.
class BackupNeedsWordsException implements Exception {
  const BackupNeedsWordsException();
  @override
  String toString() =>
      'BackupNeedsWordsException: this backup is encrypted; enter the '
      'recovery words to open it.';
}

/// A backup opened and checked, waiting for the owner to choose merge or
/// replace. On Android an encrypted file has been decrypted to a temporary
/// ZIP beside the app's data; [BackupService.discardPrepared] removes it.
class PreparedBackup {
  PreparedBackup._({
    required this.info,
    this.zipPath,
    this.zipBytes,
    this.temporary = false,
  });

  final BackupInfo info;

  /// The plain ZIP on disk (Android).
  final String? zipPath;

  /// The plain ZIP in memory (web, and the bytes API).
  final Uint8List? zipBytes;

  /// Whether [zipPath] is our own decrypted copy, to delete when done.
  final bool temporary;
}

/// Thrown when a backup archive declares more data than we will decompress —
/// the defense against a zip bomb (a tiny archive that expands to gigabytes).
class BackupTooLargeException implements Exception {
  const BackupTooLargeException(this.message);
  final String message;
  @override
  String toString() => 'BackupTooLargeException: $message';
}

/// Thrown when the MANDATORY pre-restore metadata snapshot could not be
/// saved — the restore is refused before touching anything (fail-closed,
/// BACKUP_RETENTION_SPEC §2.B in PT's plaintext idiom).
class PreRestoreSnapshotException implements Exception {
  const PreRestoreSnapshotException(this.cause);
  final Object cause;
  @override
  String toString() =>
      'PreRestoreSnapshotException: could not save the safety snapshot '
      '($cause); restore refused.';
}

class BackupService {
  final StorageService storageService;

  /// The metadata snapshot vault (plaintext .json snapshots — PT's whole
  /// backup story is plaintext-by-design). Rollback via a metadata
  /// snapshot is COMPLETE here: restore never deletes clip files (UUID
  /// names don't collide), so the old metadata simply re-adopts them.
  final BackupVault vault;

  final SharedPreferences? _prefs;

  BackupService(this.storageService,
      {required this.vault, SharedPreferences? prefs})
      : _prefs = prefs;

  /// The fleet-standard snapshot codec (C2-backup): every vault snapshot is
  /// dumped and restored through this serializer, so the wire shape is the
  /// shared [BackupEnvelope] instead of a hand-rolled composite. Reading
  /// stays tolerant of both legacy on-disk shapes.
  late final SnapshotSerializer snapshotSerializer = SnapshotSerializer(
    readMetadata: () async {
      final appDir = await FileStorage.appDocDir();
      final bytes = await FileStorage.readBytes('$appDir/metadata.json');
      if (bytes == null) return <String, Object?>{};
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : <String, Object?>{};
    },
    dumpSettings: _dumpSettings,
    writeMetadata: (metadata) async {
      final appDir = await FileStorage.appDocDir();
      final path = '$appDir/metadata.json';
      // A rollback keeps the device's pending deletes, so a clip deleted
      // after the snapshot is still offered. The snapshot's own pending
      // rows come back too unless the device has them already; a row whose
      // clip is live in the snapshot is dropped as live when it loads.
      final out = Map<String, dynamic>.from(metadata);
      final local = await _localPendingRows(path) ?? const [];
      Object? idOf(Object? row) {
        if (row is! Map) return null;
        final item = row['clip'] ?? row['compilation'];
        return item is Map ? item['id'] : null;
      }

      final ids = {for (final row in local) idOf(row)};
      final incoming = out[_pendingKey];
      // Incoming paths are pinned like a restored clip's or montage's: a
      // pending row names the files "Delete for good" destroys.
      Map<String, dynamic>? pinned(Map row) {
        final clip = row['clip'];
        if (clip is Map) {
          final c = Map<String, dynamic>.from(clip);
          final fp = c['filePath'];
          if (fp is String) {
            c['filePath'] = '$appDir/clips/${_safeBasename(fp, 'clip.mp4')}';
          }
          final tp = c['thumbnailPath'];
          if (tp is String) {
            c['thumbnailPath'] =
                '$appDir/thumbnails/${_safeBasename(tp, 'thumb.jpg')}';
          }
          return {...Map<String, dynamic>.from(row), 'clip': c};
        }
        final comp = row['compilation'];
        if (comp is Map) {
          final c = Map<String, dynamic>.from(comp);
          final fp = c['filePath'];
          if (fp is String) {
            // New montages live in the compiled folder; restored ones in
            // the app's own. Anything else is pinned to the first.
            final restored = '$appDir/compiled';
            final dir = fp.startsWith('$restored/')
                ? restored
                : storageService.compiledPath;
            c['filePath'] = '$dir/${_safeBasename(fp, 'montage.mp4')}';
          }
          return {...Map<String, dynamic>.from(row), 'compilation': c};
        }
        // An old set-aside entry the device no longer has was deleted for
        // good since the snapshot, so it does not come back.
        return null;
      }

      final merged = [
        ...local,
        if (incoming is List)
          for (final row in incoming)
            if (row is Map && !ids.contains(idOf(row)))
              if (pinned(row) case final p?) p,
      ];
      if (merged.isEmpty) {
        out.remove(_pendingKey);
      } else {
        out[_pendingKey] = merged;
      }
      await FileStorage.writeString(path, jsonEncode(out));
    },
    // A snapshot rollback must un-clobber what a replace-mode restore
    // clobbered, so settings always apply in replace mode here.
    applySettings: (settings) => _applySettings(settings, replace: true),
  );

  // Zip-bomb ceilings. Checked against the archive's header-declared sizes
  // BEFORE any entry is decompressed, so a bomb is rejected without allocating
  // its expanded payload. Generous enough for a real montage backup (a year of
  // short clips is well under a gigabyte) while stopping the petabyte case.
  static const int _maxArchiveEntries = 50000;
  static const int _maxEntryBytes = 2 * 1024 * 1024 * 1024; // 2 GB per file
  static const int _maxTotalBytes = 8 * 1024 * 1024 * 1024; // 8 GB total

  /// Rejects an archive that declares too many entries or too much uncompressed
  /// data, before it is extracted. Uses the per-entry declared size, so no
  /// decompression happens during the check.
  static void checkArchiveLimits(Archive archive) {
    if (archive.length > _maxArchiveEntries) {
      throw const BackupTooLargeException('Backup contains too many files');
    }
    var total = 0;
    for (final entry in archive) {
      final size = entry.size;
      if (size < 0 || size > _maxEntryBytes) {
        throw const BackupTooLargeException('A file in the backup is too large');
      }
      total += size;
      if (total > _maxTotalBytes) {
        throw const BackupTooLargeException(
            'Backup is too large to restore safely');
      }
    }
  }

  /// Last path segment with traversal (`..`, `.`, empty) stripped, so a restored
  /// path can never escape its target directory. Falls back to [fallback] when
  /// nothing usable remains.
  static String _safeBasename(String path, String fallback) {
    final segs = path
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    return segs.isEmpty ? fallback : segs.last;
  }

  /// A person name is written to `$facesDir/$name.jpg`, so it must be a plain
  /// basename — no separators, traversal, quotes, or control characters.
  /// Shared guard (lib/utils/person_name.dart), also applied at the
  /// export-side read loops and in StorageService.saveFaceImage.
  static bool _isSafePersonName(String name) => isSafePersonName(name);

  /// Rewrites the file paths inside restored backup metadata so they can only
  /// point inside our own media directories, and drops person keys that would
  /// escape the faces dir. Without this, a crafted backup's clip filePath (or a
  /// knownPeople key) is trusted verbatim — a later Create Backup would then
  /// read an arbitrary file into the export, or a delete would unlink it.
  static Map<String, dynamic> sanitizeRestoredMetadata(
    Map<String, dynamic> data, {
    required String clipsDir,
    required String thumbnailsDir,
    required String facesDir,
    required String compiledDir,
  }) {
    final out = Map<String, dynamic>.from(data);

    // Pending deletes are device-local, and "Delete for good" destroys the
    // files a pending row names, so an archive never plants one.
    out.remove(StorageService.pendingDeleteKey);

    final clips = out['clips'];
    if (clips is Map) {
      for (final entry in clips.entries) {
        final list = entry.value;
        if (list is! List) continue;
        for (final clip in list) {
          if (clip is! Map) continue;
          final fp = clip['filePath'];
          if (fp is String) {
            clip['filePath'] = '$clipsDir/${_safeBasename(fp, 'clip.mp4')}';
          }
          final tp = clip['thumbnailPath'];
          if (tp is String) {
            clip['thumbnailPath'] =
                '$thumbnailsDir/${_safeBasename(tp, 'thumb.jpg')}';
          }
        }
      }
    }

    // Compilation paths get the same pinning as clips: _shareCompilation
    // reads the path, delete unlinks it, and createBackup now reads it into
    // the archive — none of those may follow a foreign absolute path. It is
    // also the migration fix: a restored row pointing at the previous
    // install's storage is re-based onto our own compiled dir, where the
    // extracted montage file (when the backup carried one) actually lives.
    final comps = out['compilations'];
    if (comps is List) {
      for (final comp in comps) {
        if (comp is! Map) continue;
        final fp = comp['filePath'];
        if (fp is String) {
          comp['filePath'] = '$compiledDir/${_safeBasename(fp, 'montage.mp4')}';
        }
      }
    }

    final people = out['knownPeople'];
    if (people is Map) {
      final safe = <String, dynamic>{};
      for (final entry in people.entries) {
        final key = entry.key;
        if (key is String && _isSafePersonName(key)) safe[key] = entry.value;
      }
      out['knownPeople'] = safe;
    }

    return out;
  }

  static const _pendingKey = StorageService.pendingDeleteKey;

  /// [metadata] with no pending-delete rows. Bytes that do not parse go as
  /// they are: the backup must still carry what the device has.
  static Uint8List _withoutPending(Uint8List metadata) {
    try {
      final data = jsonDecode(utf8.decode(metadata));
      if (data is! Map<String, dynamic> || !data.containsKey(_pendingKey)) {
        return metadata;
      }
      data.remove(_pendingKey);
      return Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } catch (_) {
      return metadata;
    }
  }

  /// The pending-delete rows in the live metadata.json, or null.
  static Future<List<dynamic>?> _localPendingRows(String metadataPath) async {
    try {
      final content = await FileStorage.readString(metadataPath);
      if (content == null) return null;
      final data = jsonDecode(content);
      if (data is! Map) return null;
      final rows = data[_pendingKey];
      return rows is List && rows.isNotEmpty ? rows : null;
    } catch (_) {
      return null;
    }
  }

  /// Estimate backup size in bytes (clips + thumbnails + faces + montages
  /// + metadata). [includeMontages] mirrors the createBackup option so the
  /// estimate shown next to the toggle is honest.
  Future<int> getBackupSize({bool includeMontages = true}) async {
    // The same list createBackup packs, so the estimate cannot drift from
    // the file. On Android each size is a length lookup: reading every clip
    // just to count it would cost as much as the backup itself.
    var totalSize = 10000; // metadata and settings overhead estimate
    for (final entry in await _entries(includeMontages: includeMontages)) {
      final path = entry.sourcePath;
      if (path == null) continue;
      totalSize += BackupFiles.streams
          ? await BackupFiles.length(path)
          : (await FileStorage.readBytes(path))?.length ?? 0;
    }
    return totalSize;
  }

  /// The file extension of a backup sealed with the recovery words.
  static const encryptedExtension = 'ohbs';

  /// The files a backup carries, by name in the archive. Clips and
  /// montages are named by path, not read: on Android they are streamed
  /// into the ZIP one piece at a time.
  Future<List<BackupEntry>> _entries({required bool includeMontages}) async {
    final appDir = await FileStorage.appDocDir();
    final metadataPath = '$appDir/metadata.json';
    final facesDir = '$appDir/faces';
    final entries = <BackupEntry>[];

    // Metadata, without the clips waiting on Undo or a confirmed delete:
    // their owner deleted them, so a restore elsewhere must not bring them
    // back, and their files are not packed below either.
    final metadataBytes = await FileStorage.readBytes(metadataPath);
    if (metadataBytes != null) {
      entries.add(BackupEntry.bytes(
          'metadata.json', _withoutPending(metadataBytes)));
    }

    // Settings (ADDITIVE archive entry — old app versions ignore unknown
    // entries on restore). Every pre-v2 PT backup silently lost theme,
    // reminders, pinned tags and milestones on device migration.
    final settings = await _dumpSettings();
    entries.add(BackupEntry.bytes(
        'settings.json', Uint8List.fromList(utf8.encode(jsonEncode(settings)))));

    // Clips and thumbnails
    for (final clipList in storageService.clips.values) {
      for (final clip in clipList) {
        if (await FileStorage.exists(clip.filePath)) {
          final fileName = clip.filePath.split('/').last;
          entries.add(BackupEntry.file('clips/$fileName', clip.filePath));
        }
        final thumb = clip.thumbnailPath;
        if (thumb != null && await FileStorage.exists(thumb)) {
          final fileName = thumb.split('/').last;
          entries.add(BackupEntry.file('thumbnails/$fileName', thumb));
        }
      }
    }

    // Face images (empty on web — knownPeople is always empty when face
    // recognition is disabled). Unsafe keys are skipped: sanitization runs
    // at the restore boundary, but a pre-guard metadata.json can still
    // carry one, and '$facesDir/../x.jpg' would pack a foreign file into
    // the shared zip.
    for (final name in storageService.knownPeople.keys) {
      if (!_isSafePersonName(name)) continue;
      final facePath = '$facesDir/$name.jpg';
      if (await FileStorage.exists(facePath)) {
        entries.add(BackupEntry.file('faces/$name.jpg', facePath));
      }
    }

    // Montage videos — the finished product, not just its recipe. Skips
    // silently when a file is unreadable (a row migrated from a previous
    // install whose MP4 stayed behind): the metadata row still travels, and
    // BackupInfo.montageFileCount keeps the receipt honest about the gap.
    if (includeMontages) {
      final usedNames = <String>{};
      for (final comp in storageService.compilations) {
        if (!await FileStorage.exists(comp.filePath)) continue;
        final fileName = comp.filePath.split('/').last;
        if (!usedNames.add(fileName)) continue;
        entries.add(BackupEntry.file('compilations/$fileName', comp.filePath));
      }
    }
    return entries;
  }

  /// Create a backup. On Android, writes to [outputPath]; on web, triggers
  /// a browser download. With [encryptWith] the file is sealed under the
  /// recovery words (OHBS, see [BackupStreamCipher]); without it, it is a
  /// plain ZIP.
  ///
  /// Returns the [BackupInfo] read back from the ACTUAL output — "untested
  /// backups don't count", so success copy can honestly say "Backed up and
  /// verified — N clips". A sealed file is also opened again, chunk by
  /// chunk, before it counts.
  ///
  /// On Android every step is file to file: no clip, and never the whole
  /// archive, is held in memory, so a library of many gigabytes backs up
  /// in the same memory as a small one.
  Future<BackupInfo> createBackup(
    String outputPath,
    void Function(double progress) onProgress, {
    bool includeMontages = true,
    FileKeyDeriver? encryptWith,
  }) async {
    final entries = await _entries(includeMontages: includeMontages);
    if (!BackupFiles.streams) {
      return _createInMemory(entries, onProgress, encryptWith);
    }

    final zipPath = encryptWith == null ? outputPath : '$outputPath.part';
    try {
      await BackupFiles.writeZip(zipPath, entries,
          (done) => onProgress(done / entries.length * 0.5));

      // Verify by read-back BEFORE handing the file to the user. No bomb
      // ceilings here: the guard is for UNTRUSTED incoming archives, not
      // a cap on how much of the user's own library may be backed up.
      onProgress(0.5);
      final zip = await BackupFiles.openZip(zipPath);
      final BackupInfo info;
      try {
        info = _describe(zip.archive, 0);
      } finally {
        await zip.close();
      }
      final zipLength = await BackupFiles.length(zipPath);
      if (encryptWith == null) {
        onProgress(1.0);
        return info._asFile(zipLength, encrypted: false);
      }

      await BackupFiles.writeStream(
        outputPath,
        BackupStreamCipher.encrypt(
          _counted(BackupFiles.openRead(zipPath), zipLength,
              (f) => onProgress(0.5 + f * 0.25)),
          encryptWith,
        ),
      );
      // Read the sealed file back: every chunk must open under the words,
      // and the plaintext must be the ZIP just verified, to the byte count.
      final opened = await BackupStreamCipher.decrypt(
        _counted(BackupFiles.openRead(outputPath),
            await BackupFiles.length(outputPath),
            (f) => onProgress(0.75 + f * 0.25)),
        encryptWith,
      ).fold<int>(0, (n, chunk) => n + chunk.length);
      if (opened != zipLength) {
        throw StateError('The encrypted backup did not read back whole.');
      }
      await BackupFiles.delete(zipPath);
      onProgress(1.0);
      return info._asFile(await BackupFiles.length(outputPath),
          encrypted: true);
    } catch (_) {
      // Never leave a half-written file that looks like a backup.
      await BackupFiles.delete(zipPath);
      if (zipPath != outputPath) await BackupFiles.delete(outputPath);
      rethrow;
    }
  }

  /// The web path: the browser hands over bytes, so the archive is built
  /// in memory, as it always was there.
  Future<BackupInfo> _createInMemory(
    List<BackupEntry> entries,
    void Function(double progress) onProgress,
    FileKeyDeriver? encryptWith,
  ) async {
    final archive = Archive();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final bytes =
          entry.bytes ?? await FileStorage.readBytes(entry.sourcePath!);
      if (bytes != null) {
        archive.addFile(ArchiveFile(entry.name, bytes.length, bytes));
      }
      onProgress((i + 1) / entries.length * 0.8);
    }

    onProgress(0.85);
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    onProgress(0.88);
    final info = await validateBackup(zipBytes, enforceLimits: false);

    var out = zipBytes;
    if (encryptWith != null) {
      out = await _collect(
          BackupStreamCipher.encrypt(Stream.value(zipBytes), encryptWith));
      final opened =
          await _collect(BackupStreamCipher.decrypt(Stream.value(out), encryptWith));
      if (opened.length != zipBytes.length) {
        throw StateError('The encrypted backup did not read back whole.');
      }
    }

    onProgress(0.9);
    if (kIsWeb) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      await FileStorage.downloadFile(
          out,
          encryptWith == null
              ? 'onesecond_backup_$ts.zip'
              : 'onesecond_backup_$ts.$encryptedExtension',
          encryptWith == null ? 'application/zip' : 'application/octet-stream');
    }
    onProgress(1.0);
    return info._asFile(out.length, encrypted: encryptWith != null);
  }

  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final out = BytesBuilder(copy: false);
    await for (final part in stream) {
      out.add(part);
    }
    return out.toBytes();
  }

  /// Passes [stream] through, reporting the share of [total] bytes seen.
  static Stream<List<int>> _counted(Stream<List<int>> stream, int total,
      void Function(double fraction) onFraction) async* {
    var seen = 0;
    await for (final part in stream) {
      seen += part.length;
      if (total > 0) onFraction(seen / total);
      yield part;
    }
  }

  /// Injected in tests; resolved via the singleton otherwise.
  Future<SharedPreferences> _resolvePrefs() =>
      _prefs != null ? Future.value(_prefs) : SharedPreferences.getInstance();

  /// The allowlisted user-facing settings as a JSON-encodable map.
  Future<Map<String, Object?>> _dumpSettings() async {
    final prefs = await _resolvePrefs();
    return {
      for (final key in settingsAllowlist.keys)
        if (prefs.containsKey(key)) key: prefs.get(key),
    };
  }

  /// Applies settings from a restored archive or snapshot. Only
  /// allowlisted keys with the expected type are touched. Replace-mode
  /// clobbers; merge-mode fills missing keys — except lists, which are
  /// UNIONED (restoring to recover lost pins must actually recover them).
  Future<void> _applySettings(Map<String, dynamic> settings,
      {required bool replace}) async {
    final prefs = await _resolvePrefs();
    for (final MapEntry(:key, :value) in settings.entries) {
      final expected = settingsAllowlist[key];
      if (expected == null) continue; // not user-facing — never touch

      if (expected == List && value is List) {
        final incoming = value.whereType<String>().toList();
        if (replace || !prefs.containsKey(key)) {
          await prefs.setStringList(key, incoming);
        } else {
          final merged = {...prefs.getStringList(key) ?? [], ...incoming};
          await prefs.setStringList(key, merged.toList());
        }
        continue;
      }

      if (!replace && prefs.containsKey(key)) continue;
      switch (value) {
        case final bool v when expected == bool:
          await prefs.setBool(key, v);
        case final int v when expected == int:
          await prefs.setInt(key, v);
        case final double v when expected == double:
          await prefs.setDouble(key, v);
        case final String v when expected == String:
          await prefs.setString(key, v);
        default:
          break; // wrong type for this key — skip rather than corrupt
      }
    }
  }

  /// Validate a backup ZIP from raw bytes and return info about its contents.
  ///
  /// [enforceLimits] applies the zip-bomb ceilings — always on for
  /// UNTRUSTED incoming archives; createBackup's own read-back passes
  /// false, because the guard exists for foreign input, not to cap how
  /// much of the user's own library may be backed up.
  Future<BackupInfo> validateBackup(Uint8List bytes,
      {bool enforceLimits = true, FileKeyDeriver? decryptWith}) async {
    final encrypted = BackupStreamCipher.looksEncrypted(bytes);
    final zipBytes = encrypted ? await _openBytes(bytes, decryptWith) : bytes;
    final archive = ZipDecoder().decodeBytes(zipBytes);
    if (enforceLimits) checkArchiveLimits(archive);
    return _describe(archive, bytes.length, encrypted: encrypted);
  }

  /// The plain ZIP inside sealed [bytes].
  static Future<Uint8List> _openBytes(
      Uint8List bytes, FileKeyDeriver? decryptWith) async {
    if (decryptWith == null) throw const BackupNeedsWordsException();
    return _collect(
        BackupStreamCipher.decrypt(Stream.value(bytes), decryptWith));
  }

  /// Opens a backup the owner picked and checks it, before anything is
  /// written. Give [path] on Android: an encrypted file is decrypted, in
  /// pieces, to a temporary ZIP that [restorePrepared] then reads, so it is
  /// decrypted once. Give [bytes] on web.
  ///
  /// Throws [BackupNeedsWordsException] for an encrypted file without
  /// [decryptWith], and [BackupStreamException] when the words are wrong
  /// or the file was changed or cut short. Either way nothing is kept.
  Future<PreparedBackup> prepareRestore({
    String? path,
    Uint8List? bytes,
    FileKeyDeriver? decryptWith,
  }) async {
    if (bytes != null) {
      final encrypted = BackupStreamCipher.looksEncrypted(bytes);
      final zipBytes =
          encrypted ? await _openBytes(bytes, decryptWith) : bytes;
      final archive = ZipDecoder().decodeBytes(zipBytes);
      checkArchiveLimits(archive);
      return PreparedBackup._(
        info: _describe(archive, bytes.length, encrypted: encrypted),
        zipBytes: zipBytes,
      );
    }

    final source = path!;
    final encrypted =
        BackupStreamCipher.looksEncrypted(await BackupFiles.readHead(source, 4));
    var zipPath = source;
    if (encrypted) {
      if (decryptWith == null) throw const BackupNeedsWordsException();
      zipPath = '${await FileStorage.appDocDir()}/restore_work.zip';
      try {
        await BackupFiles.writeStream(
            zipPath,
            BackupStreamCipher.decrypt(
                BackupFiles.openRead(source), decryptWith));
      } catch (_) {
        // A file that did not verify to its end is never restored from.
        await BackupFiles.delete(zipPath);
        rethrow;
      }
    }
    try {
      final zip = await BackupFiles.openZip(zipPath);
      try {
        checkArchiveLimits(zip.archive);
        return PreparedBackup._(
          info: _describe(zip.archive, await BackupFiles.length(source),
              encrypted: encrypted),
          zipPath: zipPath,
          temporary: encrypted,
        );
      } finally {
        await zip.close();
      }
    } catch (_) {
      if (encrypted) await BackupFiles.delete(zipPath);
      rethrow;
    }
  }

  /// Removes the temporary ZIP [prepareRestore] decrypted, if any. Safe to
  /// call more than once.
  Future<void> discardPrepared(PreparedBackup prepared) async {
    final zipPath = prepared.zipPath;
    if (prepared.temporary && zipPath != null) {
      await BackupFiles.delete(zipPath);
    }
  }

  /// Restores [prepared], merging or replacing, then discards it.
  Future<void> restorePrepared(
    PreparedBackup prepared,
    void Function(double progress) onProgress, {
    bool replace = false,
  }) async {
    try {
      final bytes = prepared.zipBytes;
      if (bytes != null) {
        await _restoreArchive(
            ZipDecoder().decodeBytes(bytes), onProgress, replace: replace);
        return;
      }
      final zip = await BackupFiles.openZip(prepared.zipPath!);
      try {
        await _restoreArchive(zip.archive, onProgress, replace: replace);
      } finally {
        await zip.close();
      }
    } finally {
      await discardPrepared(prepared);
    }
  }

  /// What [archive] holds. [sizeBytes] is the size of the file as picked.
  BackupInfo _describe(Archive archive, int sizeBytes,
      {bool encrypted = false}) {
    int clipCount = 0;
    int clipFileCount = 0;
    int faceCount = 0;
    int compilationCount = 0;
    int montageFileCount = 0;
    String? dateRange;

    for (final entry in archive) {
      if (entry.name.startsWith('clips/') && entry.name.endsWith('.mp4')) {
        clipFileCount++;
      }
      if (entry.name.startsWith('faces/')) {
        faceCount++;
      }
      if (entry.name.startsWith('compilations/')) {
        montageFileCount++;
      }
    }
    clipCount = clipFileCount;

    // Try to read metadata for date range
    final metadataEntry = archive.findFile('metadata.json');
    if (metadataEntry != null) {
      try {
        final content = utf8.decode(metadataEntry.content as List<int>);
        final data = jsonDecode(content) as Map<String, dynamic>;
        if (data['clips'] != null) {
          final clipsData = data['clips'] as Map<String, dynamic>;
          final dates = clipsData.keys.toList()..sort();
          if (dates.isNotEmpty) {
            dateRange = '${dates.first} to ${dates.last}';
          }
          // Count actual clips from metadata (more accurate than file count)
          clipCount = 0;
          for (final value in clipsData.values) {
            if (value is List) {
              clipCount += value.length;
            } else if (value is Map) {
              clipCount += 1;
            }
          }
        }
        compilationCount = (data['compilations'] as List?)?.length ?? 0;
      } catch (_) {}
    }

    return BackupInfo(
      clipCount: clipCount,
      clipFileCount: clipFileCount,
      dateRange: dateRange,
      sizeBytes: sizeBytes,
      faceCount: faceCount,
      compilationCount: compilationCount,
      montageFileCount: montageFileCount,
      hasSettings: archive.findFile('settings.json') != null,
      encrypted: encrypted,
    );
  }

  /// User-facing settings that travel in backups and snapshots, with their
  /// expected pref types. DELIBERATELY an allowlist: internal keys
  /// (migration flags like clips_migrated_v2, transient state) must never
  /// travel — a restored archive flipping a migration flag could corrupt
  /// a device. A wrong-typed value from a crafted/corrupt archive is
  /// skipped, never stored (SharedPreferences' typed getters would throw
  /// on every later launch).
  static const Map<String, Type> settingsAllowlist = {
    'theme_mode': int,
    'accent_color': int,
    'crt_effects': bool,
    'date_format': String,
    'visual_style': String,
    'capture_location': bool,
    'include_location_overlay': bool,
    'reminder_enabled': bool,
    'reminder_time': String,
    'pinned_tags': List,
    'pinned_locations': List,
    'celebrated_milestones': List,
    'onboarding_complete': bool,
  };

  /// Restore a backup from raw bytes (a plain ZIP, or a sealed one with
  /// [decryptWith]), merging or replacing existing data.
  ///
  /// Takes the MANDATORY pre-restore metadata snapshot first and throws
  /// [PreRestoreSnapshotException] — touching nothing — when it cannot be
  /// saved.
  Future<void> restoreBackup(
    Uint8List bytes,
    void Function(double progress) onProgress, {
    bool replace = false,
    FileKeyDeriver? decryptWith,
  }) async {
    final prepared =
        await prepareRestore(bytes: bytes, decryptWith: decryptWith);
    await restorePrepared(prepared, onProgress, replace: replace);
  }

  /// The one restore path, over an archive already checked against the
  /// zip-bomb ceilings (bytes in memory, or a ZIP file read in pieces).
  Future<void> _restoreArchive(
    Archive archive,
    void Function(double progress) onProgress, {
    required bool replace,
  }) async {
    checkArchiveLimits(archive);

    final appDir = await FileStorage.appDocDir();
    final clipsDir = '$appDir/clips';
    final thumbnailsDir = '$appDir/thumbnails';
    final facesDir = '$appDir/faces';
    // Restored montages land in the app-PRIVATE compiled dir, not the public
    // Movies dir new compiles use: writing into Movies would duplicate
    // gallery entries the user already has, and shared-storage files owned
    // by a previous install can't be overwritten anyway. Playback only
    // needs the row's filePath to point somewhere we can read.
    final compiledDir = '$appDir/compiled';
    final metadataPath = '$appDir/metadata.json';

    await _takePreRestoreSnapshot();

    await FileStorage.ensureDir(clipsDir);
    await FileStorage.ensureDir(thumbnailsDir);
    await FileStorage.ensureDir(facesDir);
    await FileStorage.ensureDir(compiledDir);

    final totalEntries = archive.length;

    // Extract files
    for (var i = 0; i < archive.length; i++) {
      final entry = archive[i];
      if (entry.isFile) {
        // Reject path traversal (ZIP Slip)
        if (!_isSafeEntryName(entry.name)) {
          onProgress((i + 1) / totalEntries * 0.8);
          continue;
        }
        String? destPath;

        if (entry.name == 'metadata.json') {
          // Handled below
        } else if (entry.name.startsWith('clips/')) {
          destPath = '$clipsDir/${entry.name.substring(6)}';
        } else if (entry.name.startsWith('thumbnails/')) {
          destPath = '$thumbnailsDir/${entry.name.substring(11)}';
        } else if (entry.name.startsWith('faces/')) {
          destPath = '$facesDir/${entry.name.substring(6)}';
        } else if (entry.name.startsWith('compilations/')) {
          destPath = '$compiledDir/${entry.name.substring(13)}';
        }

        if (destPath != null) {
          if (replace || !await FileStorage.exists(destPath)) {
            // In pieces on Android: a montage can be hundreds of MB.
            await BackupFiles.writeEntry(entry, destPath);
          }
        }
      }
      onProgress((i + 1) / totalEntries * 0.8);
    }

    // Restore metadata
    onProgress(0.85);
    final metadataEntry = archive.findFile('metadata.json');
    if (metadataEntry != null) {
      final content = utf8.decode(metadataEntry.content as List<int>);
      final backupData = jsonDecode(content) as Map<String, dynamic>;

      // Pin all restored file paths inside our media dirs (and drop unsafe
      // person keys) before trusting them — a crafted backup must not be able
      // to point a clip at, say, the app database.
      final safeData = sanitizeRestoredMetadata(
        backupData,
        clipsDir: clipsDir,
        thumbnailsDir: thumbnailsDir,
        facesDir: facesDir,
        compiledDir: compiledDir,
      );

      if (replace) {
        // The device's own pending deletes stay offered: a replace must
        // not strand a deleted clip's files with no row to undo them by.
        final local = await _localPendingRows(metadataPath);
        if (local != null) safeData[_pendingKey] = local;
        await FileStorage.writeString(metadataPath, jsonEncode(safeData));
      } else {
        await _mergeMetadata(safeData, metadataPath);
      }
    }

    // Settings, when the archive carries them (v2 backups; old archives
    // simply have no settings.json and skip this).
    final settingsEntry = archive.findFile('settings.json');
    if (settingsEntry != null) {
      try {
        final decoded = jsonDecode(
            utf8.decode(settingsEntry.content as List<int>));
        if (decoded is Map<String, dynamic>) {
          await _applySettings(decoded, replace: replace);
        }
      } catch (_) {
        // A malformed settings entry never blocks the data restore.
      }
    }

    onProgress(0.95);

    // The one reset path: re-reads the journal and tells every screen
    // and the app-wide Undo that what they hold is old.
    await storageService.reload();
    onProgress(1.0);
  }

  /// Writes a vault snapshot [id] back as the live metadata + settings —
  /// the rollback path. Rolling back is itself a restore, so it takes its
  /// own mandatory pre-restore snapshot first. Throws [StateError] for an
  /// unknown id or a snapshot that is not valid — a corrupt snapshot must
  /// never be silently written over the live journal index.
  Future<void> restoreMetadataSnapshot(
    String id,
    void Function(double progress) onProgress,
  ) async {
    final bytes = await vault.read(id);
    if (bytes == null) {
      throw StateError('Snapshot $id is missing from the vault.');
    }

    // Validate BEFORE the mandatory snapshot or any write. The serializer
    // understands every snapshot generation (envelope-wrapped, legacy
    // composite, legacy raw metadata) and refuses anything unrestorable.
    try {
      SnapshotSerializer.parse(bytes);
    } on Object {
      throw StateError('Snapshot $id is not readable, so nothing was changed.');
    }
    onProgress(0.2);

    await _takePreRestoreSnapshot();
    onProgress(0.6);

    // The snapshot's settings complete the rollback: replace-mode restores
    // clobber prefs, so rolling back must un-clobber them (the serializer
    // applies them in replace mode).
    await snapshotSerializer.restoreAll(bytes);
    await storageService.reload();
    onProgress(1.0);
  }

  /// BACKUP_RETENTION_SPEC trigger 3 — the silent staleness net: when the
  /// vault's newest snapshot is older than 7 days (or the vault is empty),
  /// quietly vault the same composite the pre-restore net saves (metadata
  /// + allowlisted settings), so a device that never restores still always
  /// has a recent rollback point. No nag, no badge — it just happens.
  ///
  /// NEVER throws to the UI: the vault swallows exporter/store failures,
  /// and the outer guard covers everything before the vault is reached
  /// (e.g. no documents dir yet). Returns whether a snapshot was taken.
  Future<bool> maybeFreshnessSnapshot() async {
    try {
      return await vault.maybeFreshnessSnapshot(snapshotSerializer.dumpAll);
    } on Object {
      return false; // freshness is a background kindness, never an error
    }
  }

  /// The fail-closed safety net, BEFORE anything is written: current
  /// metadata (or `{}` on a fresh install — uniform rollback semantics)
  /// PLUS the allowlisted settings, because replace-mode restores clobber
  /// those too and the rollback promise has to cover what the restore can
  /// change.
  Future<void> _takePreRestoreSnapshot() async {
    try {
      await vault.save(await snapshotSerializer.dumpAll(),
          label: VaultLabel.preRestore);
    } catch (e) {
      throw PreRestoreSnapshotException(e);
    }
  }

  /// Returns true if the ZIP entry name is free of path traversal sequences.
  static bool _isSafeEntryName(String name) {
    final parts = name.split('/');
    return !parts.any((p) => p == '..' || p == '.' || p.isEmpty && parts.length > 1);
  }

  Future<void> _mergeMetadata(
      Map<String, dynamic> backupData, String metadataPath) async {
    Map<String, dynamic> existingData = {};

    final content = await FileStorage.readString(metadataPath);
    if (content != null) {
      try {
        existingData = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {}
    }

    // Merge clips
    final existingClips =
        existingData['clips'] as Map<String, dynamic>? ?? {};
    final backupClips = backupData['clips'] as Map<String, dynamic>? ?? {};

    for (final entry in backupClips.entries) {
      if (!existingClips.containsKey(entry.key)) {
        existingClips[entry.key] = entry.value;
      } else {
        // Merge clip lists — add any clips with IDs not already present
        final existingList = existingClips[entry.key];
        final backupList = entry.value;
        if (existingList is List && backupList is List) {
          final existingIds = existingList
              .whereType<Map<String, dynamic>>()
              .map((c) => c['id'] as String?)
              .toSet();
          for (final backupClip in backupList) {
            if (backupClip is Map<String, dynamic>) {
              if (!existingIds.contains(backupClip['id'])) {
                existingList.add(backupClip);
              }
            }
          }
        }
      }
    }

    existingData['clips'] = existingClips;

    // Merge known people
    final existingPeople =
        existingData['knownPeople'] as Map<String, dynamic>? ?? {};
    final backupPeople =
        backupData['knownPeople'] as Map<String, dynamic>? ?? {};
    for (final entry in backupPeople.entries) {
      if (!existingPeople.containsKey(entry.key)) {
        existingPeople[entry.key] = entry.value;
      }
    }
    existingData['knownPeople'] = existingPeople;

    // Merge compilations — add any with IDs not already present
    final existingComps = (existingData['compilations'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final backupComps = (backupData['compilations'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final existingCompIds = existingComps.map((c) => c['id'] as String?).toSet();
    for (final comp in backupComps) {
      if (!existingCompIds.contains(comp['id'])) {
        existingComps.add(comp);
      }
    }
    existingData['compilations'] = existingComps;

    await FileStorage.writeString(metadataPath, jsonEncode(existingData));
  }
}
