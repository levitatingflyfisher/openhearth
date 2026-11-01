// A deliberate delete does not ask; it happens at once and offers an Undo
// that never times out (fleet delete ruling, 2026-09-26). For that Undo to
// be real, a delete must take the clip off the calendar WITHOUT destroying
// its files, and only an Undo that lapses may destroy them.
//
// These tests pin the three halves of that contract on the real storage
// service over a real directory:
//   * removeClip takes the row out of metadata and leaves the files,
//   * restoreClip puts the same row back where it was (a day's first clip is
//     its thumbnail, so the position matters),
//   * a removed clip stays pending, files and row, across a kill and any
//     number of starts (owner ruling, board-0124), and only deleteForGood,
//     which the app calls after a confirm, destroys its files.
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
  late StorageService storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_soft_delete_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    await storage.initialize();
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

  test('removeClip takes the clip off the calendar and keeps its files',
      () async {
    final clip = await addClip('a', '2026-09-04');

    final removed = await storage.removeClip('a');

    expect(removed, isNotNull);
    expect(storage.hasClipForDate('2026-09-04'), isFalse);
    expect(File(clip.filePath).existsSync(), isTrue);
    expect(File(clip.thumbnailPath!).existsSync(), isTrue);
  });

  test('restoreClip puts it back in the same place in its day', () async {
    await addClip('first', '2026-09-04');
    await addClip('second', '2026-09-04');
    await addClip('third', '2026-09-04');

    final removed = await storage.removeClip('first');
    await storage.restoreClip(removed!);

    expect(storage.getClipsForDate('2026-09-04').map((c) => c.id),
        ['first', 'second', 'third']);
  });

  test('restore survives a reload of the metadata file', () async {
    await addClip('a', '2026-09-04');
    final removed = await storage.removeClip('a');
    await storage.restoreClip(removed!);

    final reloaded = StorageService(prefs);
    await reloaded.initialize();
    expect(reloaded.hasClipForDate('2026-09-04'), isTrue);
  });

  test('deleteForGood destroys the files and the pending entry', () async {
    final clip = await addClip('a', '2026-09-04');
    final removed = await storage.removeClip('a');

    await storage.deleteForGood(removed!);

    expect(File(clip.filePath).existsSync(), isFalse);
    expect(File(clip.thumbnailPath!).existsSync(), isFalse);
    expect(storage.pendingClipRemovals, isEmpty);
    final next = StorageService(prefs);
    await next.initialize();
    expect(next.pendingClipRemovals, isEmpty);
  });

  // Owner ruling (board-0124): keep the deleted clip's file and offer Undo
  // at the next start; a clip is destroyed only after the owner really
  // confirms. Before it, a kill with the Undo on screen destroyed the clip.
  test('a kill with Undo on screen keeps the files and the metadata entry',
      () async {
    final clip = await addClip('a', '2026-09-04');
    await storage.removeClip('a');

    // The app died with the Undo still on screen. The next start runs what
    // main() runs.
    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    expect(File(clip.filePath).existsSync(), isTrue);
    expect(File(clip.thumbnailPath!).existsSync(), isTrue);
    expect(next.pendingClipRemovals.map((r) => r.clip.id), ['a']);
    expect(next.pendingClipRemovals.single.clip.date, '2026-09-04');
  });

  test('Undo after a restart puts the clip back in its place in its day',
      () async {
    await addClip('first', '2026-09-04');
    await addClip('second', '2026-09-04');
    await addClip('third', '2026-09-04');
    await storage.removeClip('second');

    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();
    await next.restoreClip(next.pendingClipRemovals.single);

    expect(next.getClipsForDate('2026-09-04').map((c) => c.id),
        ['first', 'second', 'third']);
    expect(next.pendingClipRemovals, isEmpty);
    final again = StorageService(prefs);
    await again.initialize();
    expect(again.getClipsForDate('2026-09-04').map((c) => c.id),
        ['first', 'second', 'third']);
    expect(again.pendingClipRemovals, isEmpty);
  });

  test('a pending clip stays pending across any number of starts', () async {
    final clip = await addClip('a', '2026-09-04');
    await storage.removeClip('a');

    for (var i = 0; i < 3; i++) {
      final next = StorageService(prefs);
      await next.initialize();
      await next.keepOldPendingFiles();
      expect(next.pendingClipRemovals, hasLength(1));
    }
    expect(File(clip.filePath).existsSync(), isTrue);
  });

  test('deleteForGood never touches a file a live clip names', () async {
    final clip = await addClip('a', '2026-09-04');
    final removed = await storage.removeClip('a');
    // A second row naming the same file (a merge restore can bring one).
    await storage.addClip(clip.copyWith(id: 'b'));

    await storage.deleteForGood(removed!);

    expect(File(clip.filePath).existsSync(), isTrue);
    expect(storage.pendingClipRemovals, isEmpty);
  });

  test('a pending clip is left out of the day, montages and year review',
      () async {
    await addClip('keep', '2026-09-03');
    await addClip('gone', '2026-09-04');
    await storage.removeClip('gone');

    final next = StorageService(prefs);
    await next.initialize();
    for (final s in [storage, next]) {
      expect(s.hasClipForDate('2026-09-04'), isFalse);
      expect(s.clipCountForDate('2026-09-04'), 0);
      expect(s.getClipsForDate('2026-09-04'), isEmpty);
      expect(s.datesWithClips, {'2026-09-03'});
      expect(s.totalClips, 1);
      // Montage ranges.
      expect(s.getClipsInRange('2026-09-01', '2026-09-30').map((c) => c.id),
          ['keep']);
      expect(
          s
              .getClipsInRangeFiltered('2026-09-01', '2026-09-30')
              .map((c) => c.id),
          ['keep']);
      // Year review.
      expect(s.uniqueDatesInRange('2026-01-01', '2026-12-31'), {'2026-09-03'});
      expect(s.getClipsForMonth(2026, 9).map((c) => c.id), ['keep']);
    }
  });

  // Before the ruling, a pending clip's files were listed in prefs and
  // destroyed at the next start. Such a file has lost its row, but it is
  // still a clip that cannot be made again, so it stays on disk, and it
  // becomes an entry its owner can see and choose for (board-0138).
  test('a clip file listed by an older build is kept as an entry',
      () async {
    final video = File('${tmp.path}/clips/old.mp4');
    final thumb = File('${tmp.path}/thumbnails/old.jpg');
    await video.writeAsBytes([1]);
    await thumb.writeAsBytes([2]);
    await prefs.setStringList(
        'pending_removal_files', [video.path, thumb.path]);

    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    expect(video.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);
    final kept = next.setAsideFiles.single;
    expect(kept.isMontage, isFalse);
    expect(kept.files.toSet(), {video.path, thumb.path});
    expect(prefs.getStringList('pending_removal_files'), isNull);

    // The entry outlives the prefs list it came from.
    final again = StorageService(prefs);
    await again.initialize();
    await again.keepOldPendingFiles();
    expect(again.setAsideFiles.single.files.toSet(), {video.path, thumb.path});
  });

  // Owner ruling (board-0138): montages get the same protection, so a
  // montage file an older build listed for purge is kept too.
  test('a montage file listed by an older build is kept as an entry',
      () async {
    final montage =
        File('${storage.compiledPath}/2026-07-01_to_2026-07-31_1.mp4');
    await montage.writeAsBytes([1]);
    await prefs.setStringList('pending_removal_files', [montage.path]);

    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    expect(montage.existsSync(), isTrue);
    expect(next.setAsideFiles.single.isMontage, isTrue);
    expect(next.setAsideFiles.single.files, [montage.path]);
  });

  test('an older build\'s listed file that is gone, live, or outside the '
      'media folders makes no entry', () async {
    final live = await addClip('live', '2026-09-04');
    final outside = File('${tmp.path}/elsewhere.mp4');
    await outside.writeAsBytes([1]);
    await prefs.setStringList('pending_removal_files', [
      '${tmp.path}/clips/gone.mp4',
      live.filePath,
      outside.path,
    ]);

    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    expect(next.setAsideFiles, isEmpty);
    expect(File(live.filePath).existsSync(), isTrue);
    expect(outside.existsSync(), isTrue);
  });

  test('deleteForGood destroys an old set-aside file and its entry',
      () async {
    final video = File('${tmp.path}/clips/old.mp4');
    await video.writeAsBytes([1]);
    await prefs.setStringList('pending_removal_files', [video.path]);
    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    await next.deleteForGood(next.setAsideFiles.single);

    expect(video.existsSync(), isFalse);
    expect(next.setAsideFiles, isEmpty);
    final again = StorageService(prefs);
    await again.initialize();
    expect(again.setAsideFiles, isEmpty);
  });

  test('an undone removal is not purged on the next start', () async {
    final clip = await addClip('a', '2026-09-04');
    final removed = await storage.removeClip('a');
    await storage.restoreClip(removed!);

    final next = StorageService(prefs);
    await next.initialize();
    await next.keepOldPendingFiles();

    expect(next.hasClipForDate('2026-09-04'), isTrue);
    expect(File(clip.filePath).existsSync(), isTrue);
  });

  test('restore and remove both tell listeners the clips changed', () async {
    await addClip('a', '2026-09-04');
    var changes = 0;
    storage.changes.addListener(() => changes++);

    final removed = await storage.removeClip('a');
    await storage.restoreClip(removed!);

    expect(changes, 2);
  });

  group('montages', () {
    Future<Compilation> addMontage(String id) async {
      final file = File('${tmp.path}/compiled/$id.mp4');
      await file.parent.create(recursive: true);
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

    test('removeCompilation keeps the file; restore puts the row back',
        () async {
      await addMontage('m1');
      final m2 = await addMontage('m2');

      final removed = await storage.removeCompilation('m2');
      expect(storage.compilations.map((c) => c.id), ['m1']);
      expect(File(m2.filePath).existsSync(), isTrue);

      await storage.restoreCompilation(removed!);
      expect(storage.compilations.map((c) => c.id), ['m1', 'm2']);
    });

    // Owner ruling (board-0138): montages get the same protection as clips.
    test('a pending montage survives a kill, row and file, in its place',
        () async {
      await addMontage('m1');
      final m2 = await addMontage('m2');
      await addMontage('m3');
      await storage.removeCompilation('m2');

      for (var i = 0; i < 3; i++) {
        final next = StorageService(prefs);
        await next.initialize();
        await next.keepOldPendingFiles();
        expect(File(m2.filePath).existsSync(), isTrue);
        expect(next.compilations.map((c) => c.id), ['m1', 'm3']);
        expect(next.pendingCompilationRemovals.map((r) => r.compilation.id),
            ['m2']);
      }

      final next = StorageService(prefs);
      await next.initialize();
      await next.restoreCompilation(next.pendingCompilationRemovals.single);
      expect(next.compilations.map((c) => c.id), ['m1', 'm2', 'm3']);
      final again = StorageService(prefs);
      await again.initialize();
      expect(again.compilations.map((c) => c.id), ['m1', 'm2', 'm3']);
      expect(again.pendingCompilationRemovals, isEmpty);
    });

    test('deleteForGood destroys a pending montage and its entry', () async {
      final m1 = await addMontage('m1');
      final removed = await storage.removeCompilation('m1');

      await storage.deleteForGood(removed!);

      expect(File(m1.filePath).existsSync(), isFalse);
      expect(storage.pendingCompilationRemovals, isEmpty);
      final next = StorageService(prefs);
      await next.initialize();
      expect(next.pendingCompilationRemovals, isEmpty);
    });

    test('deleteForGood never touches a file a live montage names', () async {
      final m1 = await addMontage('m1');
      final removed = await storage.removeCompilation('m1');
      await storage.addCompilation(Compilation(
        id: 'm9',
        title: 'm9',
        filePath: m1.filePath,
        clipIds: const [],
        createdAt: DateTime(2026, 9, 2),
      ));

      await storage.deleteForGood(removed!);

      expect(File(m1.filePath).existsSync(), isTrue);
      expect(storage.pendingCompilationRemovals, isEmpty);
    });
  });
}
