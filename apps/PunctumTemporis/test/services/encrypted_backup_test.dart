// A backup sealed with the household's recovery words, end to end through
// the real BackupService: create, verify, restore, and every way a restore
// must refuse (no words, wrong words, a file cut short) without leaving a
// decrypted copy behind or touching the journal.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/services/backup_key.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/backup_stream_cipher.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late StorageService storage;
  late SharedPreferences prefs;
  late InMemoryVaultStore vaultStore;

  // One phrase for the whole file: PBKDF2 per derive is real work.
  final phrase = OpenHearthMnemonic.generate();
  final otherPhrase = OpenHearthMnemonic.generate();
  late FileKeyDeriver words;
  late FileKeyDeriver wrongWords;

  setUpAll(() async {
    words = await BackupKey.fromPhrase(phrase);
    wrongWords = await BackupKey.fromPhrase(otherPhrase);
  });

  BackupService service() => BackupService(
        storage,
        vault: BackupVault(vaultStore, appId: 'punctum', extension: 'json'),
        prefs: prefs,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_encrypted_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    await storage.initialize();
    vaultStore = InMemoryVaultStore();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// A clip whose video is [size] bytes of a pattern, so a restore can be
  /// checked byte for byte.
  Future<Uint8List> addClip(String id, String date, {int size = 3000}) async {
    final bytes = Uint8List.fromList(
        List<int>.generate(size, (i) => (i * 13 + id.length) & 0xff));
    final video = File('${tmp.path}/clips/$id.mp4');
    final thumb = File('${tmp.path}/thumbnails/$id.jpg');
    await video.parent.create(recursive: true);
    await thumb.parent.create(recursive: true);
    await video.writeAsBytes(bytes);
    await thumb.writeAsBytes([4, 5, 6]);
    await storage.addClip(Clip(
      id: id,
      date: date,
      filePath: video.path,
      thumbnailPath: thumb.path,
      type: ClipType.video,
      createdAt: DateTime(2026, 9, 1),
    ));
    return bytes;
  }

  String workZipPath() => '${tmp.path}/restore_work.zip';

  test('an encrypted backup is OHBS, verified, and leaves no ZIP beside it',
      () async {
    await addClip('a', '2026-09-01');
    await addClip('b', '2026-09-02', size: 3 * 1024 * 1024);
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';

    final info = await service().createBackup(out, (_) {}, encryptWith: words);

    final sealed = await File(out).readAsBytes();
    expect(BackupStreamCipher.looksEncrypted(sealed), isTrue);
    expect(info.encrypted, isTrue);
    expect(info.clipFileCount, 2);
    expect(info.sizeBytes, sealed.length);
    expect(File('$out.part').existsSync(), isFalse);
    // Nothing in the sealed file reads as a ZIP: no entry, no name.
    expect(ZipDecoder().decodeBytes(sealed), isEmpty);
    expect(String.fromCharCodes(sealed).contains('clips/'), isFalse);
  });

  test('an encrypted backup restores every clip byte for byte', () async {
    final a = await addClip('a', '2026-09-01');
    final b = await addClip('b', '2026-09-02', size: 3 * 1024 * 1024 + 7);
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';
    await service().createBackup(out, (_) {}, encryptWith: words);

    await Directory('${tmp.path}/clips').delete(recursive: true);

    final prepared =
        await service().prepareRestore(path: out, decryptWith: words);
    expect(prepared.info.encrypted, isTrue);
    expect(prepared.info.clipCount, 2);
    await service().restorePrepared(prepared, (_) {}, replace: true);

    expect(await File('${tmp.path}/clips/a.mp4').readAsBytes(), a);
    expect(await File('${tmp.path}/clips/b.mp4').readAsBytes(), b);
    expect(File(workZipPath()).existsSync(), isFalse,
        reason: 'the decrypted copy is removed after the restore');
    expect(storage.clips.length, 2);
  });

  test('an encrypted backup asks for the words and keeps nothing', () async {
    await addClip('a', '2026-09-01');
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';
    await service().createBackup(out, (_) {}, encryptWith: words);

    await expectLater(service().prepareRestore(path: out),
        throwsA(isA<BackupNeedsWordsException>()));
    expect(File(workZipPath()).existsSync(), isFalse);
  });

  test('the wrong words fail, keep no decrypted copy, and touch nothing',
      () async {
    await addClip('a', '2026-09-01');
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';
    await service().createBackup(out, (_) {}, encryptWith: words);
    final snapshotsBefore = (await vaultStore.list()).length;

    await expectLater(
        service().prepareRestore(path: out, decryptWith: wrongWords),
        throwsA(isA<BackupStreamException>()));
    expect(File(workZipPath()).existsSync(), isFalse);
    expect((await vaultStore.list()).length, snapshotsBefore,
        reason: 'a refused file never reaches the pre-restore snapshot');
  });

  test('a backup cut short fails and keeps no decrypted copy', () async {
    await addClip('a', '2026-09-01', size: 3 * 1024 * 1024);
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';
    await service().createBackup(out, (_) {}, encryptWith: words);
    final sealed = await File(out).readAsBytes();
    // Cut at the end of the first chunk: what is left is still a well
    // formed prefix, sealed as not final.
    final cut = '${tmp.path}/cut.${BackupService.encryptedExtension}';
    await File(cut).writeAsBytes(sealed.sublist(
        0,
        BackupStreamCipher.headerLength +
            BackupStreamCipher.defaultChunkSize +
            BackupStreamCipher.tagLength));

    await expectLater(service().prepareRestore(path: cut, decryptWith: words),
        throwsA(isA<BackupStreamException>()));
    expect(File(workZipPath()).existsSync(), isFalse);
  });

  test('a plain backup is still a plain ZIP and restores from its path',
      () async {
    final a = await addClip('a', '2026-09-01');
    final out = '${tmp.path}/backup.zip';
    final info = await service().createBackup(out, (_) {});

    expect(info.encrypted, isFalse);
    final archive = ZipDecoder().decodeBytes(await File(out).readAsBytes());
    expect(archive.findFile('clips/a.mp4'), isNotNull);

    await Directory('${tmp.path}/clips').delete(recursive: true);
    final prepared = await service().prepareRestore(path: out);
    expect(prepared.temporary, isFalse);
    await service().restorePrepared(prepared, (_) {}, replace: true);
    expect(await File('${tmp.path}/clips/a.mp4').readAsBytes(), a);
    expect(File(out).existsSync(), isTrue,
        reason: 'the picked file itself is never deleted');
  });

  test('clips are stored, not deflated, and JSON is deflated', () async {
    await addClip('a', '2026-09-01');
    final out = '${tmp.path}/backup.zip';
    await service().createBackup(out, (_) {});
    final archive = ZipDecoder().decodeBytes(await File(out).readAsBytes());
    expect(archive.findFile('clips/a.mp4')!.compression,
        CompressionType.none);
    expect(archive.findFile('metadata.json')!.compression,
        CompressionType.deflate);
  });

  test('the bytes API (web) opens a sealed backup with the words', () async {
    final a = await addClip('a', '2026-09-01');
    final out = '${tmp.path}/backup.${BackupService.encryptedExtension}';
    await service().createBackup(out, (_) {}, encryptWith: words);
    final sealed = await File(out).readAsBytes();

    await expectLater(service().validateBackup(sealed),
        throwsA(isA<BackupNeedsWordsException>()));
    final info = await service().validateBackup(sealed, decryptWith: words);
    expect(info.encrypted, isTrue);
    expect(info.clipCount, 1);

    await Directory('${tmp.path}/clips').delete(recursive: true);
    await service()
        .restoreBackup(sealed, (_) {}, replace: true, decryptWith: words);
    expect(await File('${tmp.path}/clips/a.mp4').readAsBytes(), a);
  });

  test('the size estimate matches what a backup packs', () async {
    await addClip('a', '2026-09-01', size: 5000);
    await addClip('b', '2026-09-02', size: 7000);
    // Two clips of 5000 and 7000 bytes, two thumbnails of 3, plus the
    // fixed metadata allowance.
    expect(await service().getBackupSize(), 5000 + 7000 + 3 + 3 + 10000);
  });

  group('BackupKey', () {
    test('the same words give the same file key; other words do not',
        () async {
      final salt = Uint8List(32)..[0] = 9;
      final again = await BackupKey.fromPhrase('  ${phrase.toUpperCase()} ');
      expect(await again(salt), await words(salt));
      expect(await wrongWords(salt), isNot(await words(salt)));
    });

    test('each file salt gives its own key', () async {
      expect(await words(Uint8List(32)), isNot(await words(Uint8List(32)..[5] = 1)));
    });

    test('only 12 valid words pass', () {
      expect(BackupKey.isValidPhrase(phrase), isTrue);
      expect(BackupKey.isValidPhrase('not twelve words'), isFalse);
    });
  });
}
