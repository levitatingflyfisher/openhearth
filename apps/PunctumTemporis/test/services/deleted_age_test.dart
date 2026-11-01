// How long a deleted item has waited (owner rulings, board-0138, and
// board-0167, which kept the 30 days as built): nothing
// is destroyed on a timer. An item counts as old once it is more than
// StorageService.deletedKeepDays calendar days past its delete, or past the
// last time its owner chose Keep. Calendar days, not 24-hour blocks, so a
// clock change between the two dates cannot move the answer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/models/clip.dart';
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
  late DateTime now;

  Future<StorageService> start() async {
    final s = StorageService(prefs, clock: () => now);
    await s.initialize();
    await s.keepOldPendingFiles();
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_deleted_age_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> addAndRemove(StorageService s, String id) async {
    final video = File('${tmp.path}/clips/$id.mp4');
    await video.writeAsBytes([1, 2, 3]);
    await s.addClip(Clip(
      id: id,
      date: '2026-09-04',
      filePath: video.path,
      type: ClipType.video,
      createdAt: DateTime(2026, 9, 4),
    ));
    await s.removeClip(id);
    return video;
  }

  test('the keep time is one named constant of 30 days', () {
    expect(StorageService.deletedKeepDays, 30);
  });

  test('31 calendar days across the autumn clock change is old; 29 is not',
      () async {
    // Deleted late on Oct 15; Nov 15 just after midnight is 31 calendar
    // days on, though only 30 days and under 2 hours have passed. In New
    // York the clocks went back on Nov 1 in between.
    now = DateTime(2026, 10, 15, 23, 30);
    final storage = await start();
    final a = await addAndRemove(storage, 'a');
    now = DateTime(2026, 10, 17, 0, 10);
    await addAndRemove(storage, 'b');

    now = DateTime(2026, 11, 15, 0, 10);
    expect(storage.oldRemovals.map((r) => r.id), ['a']);

    // The delete time survives a restart.
    final next = await start();
    expect(next.oldRemovals.map((r) => r.id), ['a']);
    expect(a.existsSync(), isTrue);
  });

  test('Keep leaves the item and its files, and asks again 30 days later',
      () async {
    now = DateTime(2026, 9, 1, 12);
    final storage = await start();
    final a = await addAndRemove(storage, 'a');

    now = DateTime(2026, 10, 15, 9);
    final next = await start();
    expect(next.oldRemovals.map((r) => r.id), ['a']);

    await next.keepForNow(next.oldRemovals);

    expect(next.oldRemovals, isEmpty);
    expect(next.pendingClipRemovals.map((r) => r.id), ['a']);
    expect(a.existsSync(), isTrue);
    expect((await start()).oldRemovals, isEmpty);

    // 30 days after Keep is not more than 30; the day after is.
    now = DateTime(2026, 11, 14, 23);
    expect((await start()).oldRemovals, isEmpty);
    now = DateTime(2026, 11, 15, 0, 30);
    expect((await start()).oldRemovals.map((r) => r.id), ['a']);
  });

  test('deleteOld destroys only the old items, files and entries', () async {
    now = DateTime(2026, 9, 1, 12);
    final storage = await start();
    final a = await addAndRemove(storage, 'a');
    now = DateTime(2026, 10, 1, 12);
    final b = await addAndRemove(storage, 'b');

    now = DateTime(2026, 10, 5, 12);
    final next = await start();
    await next.deleteForGoodAll(next.oldRemovals);

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
    expect(next.pendingClipRemovals.map((r) => r.id), ['b']);
    expect((await start()).pendingClipRemovals.map((r) => r.id), ['b']);
  });

  test('a pending row with no delete time is dated at the next start',
      () async {
    now = DateTime(2026, 9, 1, 12);
    final storage = await start();
    await addAndRemove(storage, 'a');
    // A row as 4e81596 wrote it: no delete time.
    final meta = File('${tmp.path}/metadata.json');
    await meta.writeAsString((await meta.readAsString())
        .replaceAll(RegExp(r',?"deletedAt":"[^"]*"'), ''));

    now = DateTime(2026, 9, 10, 12);
    await start();
    now = DateTime(2026, 10, 10, 12);
    expect((await start()).oldRemovals, isEmpty);
    now = DateTime(2026, 10, 11, 12);
    expect((await start()).oldRemovals.map((r) => r.id), ['a']);
  });
}
