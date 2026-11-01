// A clip waiting on its owner's choice after a delete (owner ruling,
// board-0124) is device-local, like the Undo it stands for:
//   * a backup leaves it out, row and files, so a restore elsewhere never
//     brings back a clip its owner deleted,
//   * a restore never drops the device's own pending clips, so they are
//     still offered, and never plants one from the archive (a pending row
//     names files that "Delete for good" destroys),
//   * a snapshot rollback keeps the device's pending clips too.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
  late BackupVault vault;

  BackupService service() =>
      BackupService(storage, vault: vault, prefs: prefs);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_pending_backup_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    await storage.initialize();
    vault = BackupVault(InMemoryVaultStore(),
        appId: 'punctum', extension: 'json');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<Clip> addClip(String id, String date) async {
    final video = File('${tmp.path}/clips/$id.mp4');
    final thumb = File('${tmp.path}/thumbnails/$id.jpg');
    await video.writeAsBytes([1, 2, 3]);
    await thumb.writeAsBytes([4, 5, 6]);
    final clip = Clip(
      id: id,
      date: date,
      filePath: video.path,
      thumbnailPath: thumb.path,
      type: ClipType.video,
      createdAt: DateTime(2026, 9, 1),
    );
    await storage.addClip(clip);
    return clip;
  }

  Uint8List zipOf(Map<String, dynamic> metadata) {
    final archive = Archive();
    final bytes = utf8.encode(jsonEncode(metadata));
    archive.addFile(ArchiveFile('metadata.json', bytes.length, bytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('a backup leaves out a pending clip, row and files', () async {
    await addClip('keep', '2026-09-03');
    await addClip('gone', '2026-09-04');
    await storage.removeClip('gone');

    final out = '${tmp.path}/backup.zip';
    await service().createBackup(out, (_) {});

    final archive = ZipDecoder().decodeBytes(await File(out).readAsBytes());
    final names = archive.map((e) => e.name).toList();
    expect(names, contains('clips/keep.mp4'));
    expect(names, isNot(contains('clips/gone.mp4')));
    expect(names, isNot(contains('thumbnails/gone.jpg')));
    final meta = utf8.decode(
        archive.findFile('metadata.json')!.content as List<int>);
    expect(meta, isNot(contains('gone')));
  });

  test('the sanitizer drops pending rows an archive carries', () {
    final out = BackupService.sanitizeRestoredMetadata(
      {
        'clips': <String, dynamic>{},
        'pendingDelete': [
          {
            'index': 0,
            'clip': {'id': 'x', 'filePath': '/data/app/databases/main.db'},
          }
        ],
      },
      clipsDir: '/c',
      thumbnailsDir: '/t',
      facesDir: '/f',
      compiledDir: '/m',
    );
    expect(out.containsKey('pendingDelete'), isFalse);
  });

  test('a replace restore keeps the device\'s pending clips', () async {
    final clip = await addClip('gone', '2026-09-04');
    await storage.removeClip('gone');

    await service().restoreBackup(
      zipOf({'clips': <String, dynamic>{}, 'compilations': <dynamic>[]}),
      (_) {},
      replace: true,
    );

    expect(storage.pendingClipRemovals.map((r) => r.clip.id), ['gone']);
    expect(File(clip.filePath).existsSync(), isTrue);
  });

  test('a merge restore keeps the device\'s pending clips', () async {
    await addClip('gone', '2026-09-04');
    await storage.removeClip('gone');

    await service().restoreBackup(
      zipOf({'clips': <String, dynamic>{}, 'compilations': <dynamic>[]}),
      (_) {},
    );

    expect(storage.pendingClipRemovals.map((r) => r.clip.id), ['gone']);
  });

  test('a snapshot rollback keeps the device\'s pending clips', () async {
    // The snapshot is taken before the delete, so it knows nothing of it.
    await addClip('keep', '2026-09-03');
    await addClip('gone', '2026-09-04');
    final svc = service();
    final entry = await vault.save(await svc.snapshotSerializer.dumpAll(),
        label: VaultLabel.manual);
    await storage.removeClip('gone');
    await storage.addClip(Clip(
      id: 'later',
      date: '2026-09-05',
      filePath: '${tmp.path}/clips/later.mp4',
      type: ClipType.video,
      createdAt: DateTime(2026, 9, 5),
    ));
    final later = await storage.removeClip('later');

    await svc.restoreMetadataSnapshot(entry.id, (_) {});

    // 'gone' is live again in the snapshot, so it is not also pending.
    expect(storage.hasClipForDate('2026-09-04'), isTrue);
    expect(storage.pendingClipRemovals.map((r) => r.clip.id), ['later']);
    expect(later, isNotNull);
  });

  // Owner ruling (board-0138): a montage gets the same protection.
  group('montages', () {
    Future<Compilation> addMontage(String id) async {
      final file = File('${storage.compiledPath}/$id.mp4');
      await file.writeAsBytes([7, 8, 9]);
      final comp = Compilation(
        id: id,
        title: id,
        filePath: file.path,
        clipIds: const [],
        createdAt: DateTime(2026, 9, 1),
      );
      await storage.addCompilation(comp);
      return comp;
    }

    test('a backup leaves out a pending montage', () async {
      await addMontage('gone');
      await storage.removeCompilation('gone');

      final out = '${tmp.path}/backup.zip';
      await service().createBackup(out, (_) {});

      final archive = ZipDecoder().decodeBytes(await File(out).readAsBytes());
      expect(archive.map((e) => e.name),
          isNot(contains('compilations/gone.mp4')));
      final meta = utf8.decode(
          archive.findFile('metadata.json')!.content as List<int>);
      expect(meta, isNot(contains('gone')));
    });

    test('a replace restore keeps the device\'s pending montage', () async {
      final m = await addMontage('gone');
      await storage.removeCompilation('gone');

      await service().restoreBackup(
        zipOf({'clips': <String, dynamic>{}, 'compilations': <dynamic>[]}),
        (_) {},
        replace: true,
      );

      expect(storage.pendingCompilationRemovals.map((r) => r.compilation.id),
          ['gone']);
      expect(File(m.filePath).existsSync(), isTrue);
    });

    test('a snapshot rollback keeps pending montages, its own pinned',
        () async {
      await addMontage('before');
      await storage.removeCompilation('before');
      final svc = service();
      final entry = await vault.save(await svc.snapshotSerializer.dumpAll(),
          label: VaultLabel.manual);
      // After the snapshot: 'before' comes back, 'after' goes.
      await storage.restoreCompilation(
          storage.pendingCompilationRemovals.single);
      await addMontage('after');
      await storage.removeCompilation('after');

      await svc.restoreMetadataSnapshot(entry.id, (_) {});

      expect(storage.compilations, isEmpty);
      expect(
          storage.pendingCompilationRemovals
              .map((r) => r.compilation.id)
              .toSet(),
          {'before', 'after'});
      for (final r in storage.pendingCompilationRemovals) {
        expect(r.compilation.filePath,
            startsWith('${storage.compiledPath}/'));
      }
    });
  });
}
