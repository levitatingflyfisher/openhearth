// W4: BackupSink — where the encrypted backup blob (§3.1 step 7) lands.
// The blob is already ciphertext when it reaches a sink; sinks only move
// bytes. v1 ships a file sink in a folder no automatic backup takes;
// cloud pickers are future.
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/backup_sink.dart';

void main() {
  test('FileBackupSink writes the blob verbatim and reports where', () async {
    final dir = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final sink = FileBackupSink(directory: dir.path);
    final blob = Uint8List.fromList(List.generate(64, (i) => i * 3 % 256));

    final where = await sink.save(blob);
    expect(where, contains(dir.path));

    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('.porchbackup'));
    expect(await files.single.readAsBytes(), blob);
  });

  test('a second save does not clobber the first (fresh name per save)',
      () async {
    final dir = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final sink = FileBackupSink(directory: dir.path);
    await sink.save(Uint8List.fromList([1]));
    await sink.save(Uint8List.fromList([2]));
    expect(dir.listSync().whereType<File>().length, 2);
  });

  test('the backup folder is made on first save', () async {
    final dir = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final sink = FileBackupSink(directory: '${dir.path}/$backupFolderName');
    await sink.save(Uint8List.fromList([1]));
    expect(
        Directory('${dir.path}/$backupFolderName')
            .listSync()
            .whereType<File>()
            .length,
        1);
  });

  test('the folder is marked excluded from backup before any file is '
      'written in it', () async {
    final dir = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final folder = '${dir.path}/$backupFolderName';
    final seen = <String>[];
    final sink = FileBackupSink(
      directory: folder,
      excludeFromBackup: (d) async {
        expect(Directory(d).existsSync(), isTrue,
            reason: 'the flag is set on a folder that exists');
        expect(Directory(d).listSync(), isEmpty,
            reason: 'no file before the flag');
        seen.add(d);
      },
    );
    await sink.save(Uint8List.fromList([1]));
    expect(seen, [folder]);
  });

  test('if the folder cannot be excluded from backup, no file is written',
      () async {
    final dir = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final folder = '${dir.path}/$backupFolderName';
    final sink = FileBackupSink(
      directory: folder,
      excludeFromBackup: (_) async => throw StateError('no flag'),
    );
    await expectLater(sink.save(Uint8List.fromList([1])), throwsStateError);
    expect(Directory(folder).listSync().whereType<File>(), isEmpty);
  });

  // Start over: every backup file this phone holds goes, in the backups
  // folder and in the folders where the share sheet was handed a copy.
  // Nothing else in those folders is touched.
  test('deleteAll removes the backup files and the share sheet copies, '
      'and nothing else', () async {
    final root = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => root.delete(recursive: true));
    final folder = '${root.path}/$backupFolderName';
    final shared = Directory('${root.path}/tmp');
    final sink = FileBackupSink(directory: folder, sharedCopiesRoot: shared.path);
    await sink.save(Uint8List.fromList([1]));
    await sink.save(Uint8List.fromList([2]));
    final copy = File('${shared.path}/3f1c/porch-20261115-101500.porchbackup');
    await copy.create(recursive: true);
    final other = File('${shared.path}/9a2b/photo.jpg');
    await other.create(recursive: true);

    await sink.deleteAll();

    expect(Directory(folder).existsSync(), isFalse);
    expect(copy.existsSync(), isFalse);
    expect(Directory('${shared.path}/3f1c').existsSync(), isFalse,
        reason: 'the copy’s own folder held nothing else');
    expect(other.existsSync(), isTrue);
  });

  test('deleteAll with nothing saved yet is fine', () async {
    final root = await Directory.systemTemp.createTemp('porch_backup_test');
    addTearDown(() => root.delete(recursive: true));
    final sink = FileBackupSink(
        directory: '${root.path}/$backupFolderName',
        sharedCopiesRoot: '${root.path}/missing');
    await sink.deleteAll();
  });

  test('RecordingBackupSink.deleteAll forgets what it saved', () async {
    final sink = RecordingBackupSink();
    await sink.save(Uint8List.fromList([9]));
    await sink.deleteAll();
    expect(sink.saved, isEmpty);
  });

  test('RecordingBackupSink captures blobs for tests', () async {
    final sink = RecordingBackupSink();
    await sink.save(Uint8List.fromList([9, 9]));
    expect(sink.saved.single, [9, 9]);
  });
}
