// metadata.json is the only record of which clip belongs to which day, with
// its tags and place. The clips themselves cannot be made again, and without
// this file the app has forgotten them. A file the app cannot read must
// therefore be kept whole under a dated name, never overwritten by the next
// save, while the app still opens (workshop rule: never refuse to start on
// broken state).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// A real file, except that metadata.json cannot be moved or copied: the
/// set-aside itself fails, and only the set-aside.
class _StuckFile implements File {
  _StuckFile(this._real);
  final File _real;

  bool get _isLive => _real.path.endsWith('/metadata.json');

  @override
  String get path => _real.path;
  @override
  Future<bool> exists() => _real.exists();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _real.readAsString(encoding: encoding);
  @override
  Future<Uint8List> readAsBytes() => _real.readAsBytes();
  @override
  Future<File> writeAsString(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      _real.writeAsString(contents,
          mode: mode, encoding: encoding, flush: flush);
  @override
  Future<File> rename(String newPath) async {
    if (_isLive) throw FileSystemException('no rename', path);
    return _real.rename(newPath);
  }

  @override
  Future<File> copy(String newPath) async {
    if (_isLive) throw FileSystemException('no copy', path);
    return _real.copy(newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _StuckOverrides extends IOOverrides {
  @override
  File createFile(String path) => _StuckFile(super.createFile(path));
}

Map<String, dynamic> _row(String id, String date) => {
      'id': id,
      'date': date,
      'filePath': '/clips/$id.mp4',
      'type': 'video',
      'createdAt': '${date}T12:00:00.000',
    };

Clip _clip(String id, String date) => Clip.fromJson(_row(id, date));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File live;
  late StorageService storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_set_aside_');
    live = File('${tmp.path}/metadata.json');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  List<File> setAsideFiles() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.split('/').last.startsWith('metadata.unreadable-'))
      .toList();

  const torn = '{"clips":{"2026-11-01":[{"id":"a","date":"2026-11-0';

  group('a file that cannot be read at all', () {
    test('is moved aside under a dated name and the app starts empty',
        () async {
      await live.writeAsString(torn);

      await storage.initialize();

      expect(storage.clips, isEmpty);
      expect(storage.compilations, isEmpty);
      expect(live.existsSync(), isFalse,
          reason: 'the unreadable file has moved, not been copied');
      final aside = setAsideFiles();
      expect(aside, hasLength(1));
      expect(
          aside.single.path.split('/').last,
          matches(RegExp(
              r'^metadata\.unreadable-\d{4}-\d{2}-\d{2}T[\d.-]+(-\d+)?\.json$')));
      expect(aside.single.readAsStringSync(), torn);
    });

    test('is not overwritten by the next save', () async {
      await live.writeAsString(torn);
      await storage.initialize();

      await storage.addClip(_clip('new', '2026-11-10'));

      expect(setAsideFiles().single.readAsStringSync(), torn);
      final saved = jsonDecode(live.readAsStringSync()) as Map<String, dynamic>;
      expect((saved['clips'] as Map).keys, ['2026-11-10']);
    });

    test('covers the empty file a killed write leaves', () async {
      await live.writeAsString('');

      await storage.initialize();

      expect(storage.clips, isEmpty);
      expect(setAsideFiles().single.readAsStringSync(), '');
    });

    test('covers valid JSON of the wrong shape', () async {
      await live.writeAsString('[1, 2, 3]');

      await storage.initialize();

      expect(setAsideFiles().single.readAsStringSync(), '[1, 2, 3]');
    });

    test('a second failure keeps both copies', () async {
      await live.writeAsString('first');
      await storage.initialize();
      await live.writeAsString('second');
      await storage.initialize();

      expect(setAsideFiles().map((f) => f.readAsStringSync()).toSet(),
          {'first', 'second'});
    });

    test('forgets the people of an earlier load too', () async {
      await live.writeAsString(jsonEncode({
        'clips': <String, dynamic>{},
        'compilations': <dynamic>[],
        'knownPeople': {
          'Alice': [
            [0.1, 0.2]
          ],
        },
      }));
      await storage.initialize();
      expect(storage.knownPeople.keys, ['Alice']);

      await live.writeAsString(torn);
      await storage.initialize();

      expect(storage.knownPeople, isEmpty);
    });

    test('when it cannot be moved, a save refuses and leaves it whole',
        () async {
      await live.writeAsString(torn);

      await IOOverrides.runWithIOOverrides(() async {
        await storage.initialize();
        expect(storage.clips, isEmpty, reason: 'the app still opens');
        await expectLater(
            storage.addClip(_clip('new', '2026-11-10')), throwsStateError);
      }, _StuckOverrides());

      expect(live.readAsStringSync(), torn);
      expect(setAsideFiles(), isEmpty);
    });

    test('a later save moves it aside once it can', () async {
      await live.writeAsString(torn);
      await IOOverrides.runWithIOOverrides(
          () => storage.initialize(), _StuckOverrides());

      await storage.addClip(_clip('new', '2026-11-10'));

      expect(setAsideFiles().single.readAsStringSync(), torn);
      expect(live.readAsStringSync(), contains('2026-11-10'));
    });
  });

  group('a file with one bad row', () {
    late String content;

    setUp(() async {
      content = jsonEncode({
        'clips': {
          '2026-11-01': [
            _row('good1', '2026-11-01'),
            {'id': 'no-date-or-path'},
          ],
          '2026-11-02': [
            {'id': 'only-bad'},
          ],
          '2026-11-03': _row('good2', '2026-11-03'),
        },
        'compilations': [
          {'id': 'no-title'},
        ],
        'knownPeople': {
          'Alice': [
            [0.1, 0.2]
          ],
        },
      });
      await live.writeAsString(content);
    });

    test('keeps every good row and gives no bad day an entry', () async {
      await storage.initialize();

      expect(storage.getClipsForDate('2026-11-01').map((c) => c.id), ['good1']);
      expect(storage.getClipsForDate('2026-11-03').map((c) => c.id), ['good2']);
      expect(storage.hasClipForDate('2026-11-02'), isFalse);
      expect(storage.compilations, isEmpty);
      expect(storage.knownPeople.keys, ['Alice']);
    });

    test('copies the whole original aside and leaves the live file alone',
        () async {
      await storage.initialize();

      expect(setAsideFiles().single.readAsStringSync(), content);
      expect(live.readAsStringSync(), content);
    });

    test('the next save writes the good rows and the copy stays whole',
        () async {
      await storage.initialize();

      await storage.addClip(_clip('new', '2026-11-10'));

      expect(setAsideFiles().single.readAsStringSync(), content);
      final saved = jsonDecode(live.readAsStringSync()) as Map<String, dynamic>;
      expect((saved['clips'] as Map).keys,
          ['2026-11-01', '2026-11-03', '2026-11-10']);
    });

    test('when the copy fails, the next save still does not lose the file',
        () async {
      await IOOverrides.runWithIOOverrides(() async {
        await storage.initialize();
        await expectLater(
            storage.addClip(_clip('new', '2026-11-10')), throwsStateError);
      }, _StuckOverrides());

      expect(live.readAsStringSync(), content);
    });
  });

  group('the snapshot vault', () {
    BackupService service() => BackupService(
          storage,
          vault: BackupVault(
            InMemoryVaultStore(),
            appId: 'punctum',
            extension: 'json',
          ),
        );

    test('restores the last snapshot over a set-aside start', () async {
      await live.writeAsString(jsonEncode({
        'clips': {
          '2026-11-01': [_row('kept', '2026-11-01')],
        },
        'compilations': <dynamic>[],
      }));
      await storage.initialize();
      final backup = service();
      expect(await backup.maybeFreshnessSnapshot(), isTrue);
      final id = (await backup.vault.list()).single.id;

      await live.writeAsString(torn);
      await storage.initialize();
      expect(storage.clips, isEmpty);

      await backup.restoreMetadataSnapshot(id, (_) {});

      expect(storage.getClipsForDate('2026-11-01').map((c) => c.id), ['kept']);
      expect(setAsideFiles().single.readAsStringSync(), torn,
          reason: 'restoring must not cost the set-aside file');
    });
  });
}
