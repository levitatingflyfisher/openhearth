// The owner's test for encryption at real size, through the real backup
// and restore: a synthetic library of several GB (random bytes, never a
// real clip), backed up locked with recovery words, every clip deleted,
// restored, and each clip compared by SHA-256. Prints wall time per step
// and the process's peak resident memory, so runs at 100 MB, 1 GB and
// 4 GB show whether memory stays flat as the library grows.
//
// Skipped in the normal suite. Run on real disk (never /tmp):
//   PT_SIZE_MB=1024 PT_SIZE_DIR=/path/on/disk flutter test test/size
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/services/backup_key.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show OpenHearthMnemonic;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.base);
  final String base;
  @override
  Future<String?> getApplicationDocumentsPath() async => base;
  @override
  Future<String?> getApplicationSupportPath() async => base;
  @override
  Future<String?> getTemporaryPath() async => '$base/tmp';
}

/// 2 MiB per clip: the order of a few seconds of 1080p phone video.
const _clipBytes = 2 * 1024 * 1024;

String _mib(int bytes) => (bytes / 1048576).toStringAsFixed(1);

/// Fills [out] with xorshift output: incompressible, and fast enough that
/// making 4 GB does not take longer than the backup.
int _fill(Uint8List out, int state) {
  final words = Uint32List.view(out.buffer, out.offsetInBytes, out.length ~/ 4);
  var x = state;
  for (var i = 0; i < words.length; i++) {
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    words[i] = x;
  }
  return x;
}

Future<String> _sha256(String path) async {
  final sink = Sha256().newHashSink();
  await for (final part in File(path).openRead()) {
    sink.add(part);
  }
  sink.close();
  final hash = await sink.hash();
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sizeMb = int.tryParse(Platform.environment['PT_SIZE_MB'] ?? '');
  final dir = Platform.environment['PT_SIZE_DIR'];

  test('a locked backup of the whole library restores byte for byte',
      () async {
    final base = Directory('$dir/run-${sizeMb}m');
    if (base.existsSync()) base.deleteSync(recursive: true);
    base.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(base.path);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.initialize();
    final service = BackupService(storage,
        vault: BackupVault(InMemoryVaultStore(),
            appId: 'punctum', extension: 'json'),
        prefs: prefs);
    final words = await BackupKey.fromPhrase(OpenHearthMnemonic.generate());

    // The library: clips of random bytes, each hashed as it is written.
    final clipCount = sizeMb! * 1024 * 1024 ~/ _clipBytes;
    final clipsDir = Directory('${base.path}/clips')..createSync();
    final hashes = <String, String>{};
    final block = Uint8List(_clipBytes);
    var state = 0x9e3779b9;
    final watch = Stopwatch()..start();
    final clips = <Clip>[];
    for (var i = 0; i < clipCount; i++) {
      state = _fill(block, state);
      final path = '${clipsDir.path}/clip$i.mp4';
      File(path).writeAsBytesSync(block, flush: false);
      final sink = Sha256().newHashSink()..add(block);
      sink.close();
      hashes[path] = (await sink.hash())
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final day = DateTime(2000, 1, 1).add(Duration(days: i));
      clips.add(Clip(
        id: 'clip$i',
        date: '${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
        filePath: path,
        type: ClipType.video,
        createdAt: day,
      ));
    }
    for (final clip in clips) {
      await storage.addClip(clip);
    }
    final libraryBytes = clipCount * _clipBytes;
    final makeMs = watch.elapsedMilliseconds;
    final rssAfterMake = ProcessInfo.maxRss;

    // Back up, locked: streamed ZIP, sealed, read back chunk by chunk.
    final out = '$dir/run-${sizeMb}m.${BackupService.encryptedExtension}';
    watch.reset();
    final info =
        await service.createBackup(out, (_) {}, encryptWith: words);
    final backupMs = watch.elapsedMilliseconds;
    final rssAfterBackup = ProcessInfo.maxRss;
    expect(info.encrypted, isTrue);
    expect(info.clipFileCount, clipCount);
    final outBytes = File(out).lengthSync();

    // Lose every clip, then restore from the locked file.
    clipsDir.deleteSync(recursive: true);
    watch.reset();
    final prepared =
        await service.prepareRestore(path: out, decryptWith: words);
    await service.restorePrepared(prepared, (_) {}, replace: true);
    final restoreMs = watch.elapsedMilliseconds;
    final rssAfterRestore = ProcessInfo.maxRss;

    var matched = 0;
    for (final entry in hashes.entries) {
      if (await _sha256(entry.key) == entry.value) matched++;
    }

    // ignore: avoid_print
    print('SIZE-RESULT library=${_mib(libraryBytes)}MiB clips=$clipCount '
        'output=${_mib(outBytes)}MiB make=${makeMs}ms '
        'backup=${backupMs}ms restore=${restoreMs}ms '
        'peakRSS make=${_mib(rssAfterMake)}MiB '
        'backup=${_mib(rssAfterBackup)}MiB '
        'restore=${_mib(rssAfterRestore)}MiB '
        'sha256 matched=$matched/$clipCount');

    expect(matched, clipCount);
    expect(File('${base.path}/restore_work.zip').existsSync(), isFalse);

    // The synthetic data has served its purpose.
    File(out).deleteSync();
    base.deleteSync(recursive: true);
  },
      timeout: Timeout.none,
      skip: sizeMb == null || dir == null
          ? 'size test: set PT_SIZE_MB and PT_SIZE_DIR (real disk)'
          : false);
}
