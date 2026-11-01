// The move page build reads the journal at the old address and must write
// nothing there (owner ruling, 15 Nov 2026). A read-only start makes no
// folders, never sets an unreadable file aside, and records no notice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
  late SharedPreferences prefs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_read_only_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('reads the clips and makes no folders', () async {
    await File('${tmp.path}/metadata.json').writeAsString(
        '{"clips":{"2026-11-01":[{"id":"a","date":"2026-11-01",'
        '"filePath":"/clips/a.mp4","type":"video",'
        '"createdAt":"2026-11-01T12:00:00.000"}]}}');

    final storage = StorageService(prefs);
    await storage.initialize(readOnly: true);

    expect(storage.clips.keys, ['2026-11-01']);
    expect(tmp.listSync().map((e) => e.path.split('/').last), ['metadata.json']);
    expect(prefs.getKeys(), isEmpty);
  });

  test('leaves an unreadable file where it is and records nothing', () async {
    const torn = '{"clips":{"2026-11-01":[{"id":"a","date":"2026-11-0';
    final live = File('${tmp.path}/metadata.json');
    await live.writeAsString(torn);

    final storage = StorageService(prefs);
    await storage.initialize(readOnly: true);

    expect(storage.clips, isEmpty);
    expect(live.readAsStringSync(), torn);
    expect(tmp.listSync().map((e) => e.path.split('/').last), ['metadata.json']);
    expect(prefs.getKeys(), isEmpty);
  });

  test('the normal start still makes its folders', () async {
    final storage = StorageService(prefs);
    await storage.initialize();
    expect(Directory('${tmp.path}/clips').existsSync(), isTrue);
  });
}
