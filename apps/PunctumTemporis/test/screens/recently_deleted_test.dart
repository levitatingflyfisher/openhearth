// Recently deleted (owner ruling, board-0138): "a Recently deleted list in
// Settings shows deleted clips, montages and the old set-aside clip files
// for 30 days." The earlier ruling still holds: a clip is destroyed only
// after its owner really confirms, so every "Delete for good" here asks
// first and names the item.
//
// Before: a pending clip was offered only on the calendar at the next
// start, a deleted montage had no list at all, and a clip file an older
// build set aside sat on disk with no way to see it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/screens/recently_deleted_screen.dart';
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
  late SharedPreferences prefs;
  late File video;
  late File thumb;
  late File montage;
  late File oldVideo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_recently_deleted_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'crt_effects': false,
    });
    prefs = await SharedPreferences.getInstance();
    // The run before: a clip and a montage deleted, and a clip file an
    // older build listed for purge.
    final before = StorageService(prefs);
    await before.initialize();
    video = File('${tmp.path}/clips/a.mp4');
    thumb = File('${tmp.path}/thumbnails/a.jpg');
    await video.writeAsBytes([1, 2, 3]);
    // A real picture: the list shows it.
    await thumb.writeAsBytes(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    await before.addClip(Clip(
      id: 'a',
      date: '2026-09-04',
      filePath: video.path,
      thumbnailPath: thumb.path,
      type: ClipType.video,
      createdAt: DateTime(2026, 9, 4),
    ));
    await before.removeClip('a');
    montage = File('${before.compiledPath}/m1.mp4');
    await montage.writeAsBytes([7, 8, 9]);
    await before.addCompilation(Compilation(
      id: 'm1',
      title: 'Jul 1 - Jul 31, 2026',
      filePath: montage.path,
      clipIds: const [],
      createdAt: DateTime(2026, 8, 1),
    ));
    await before.removeCompilation('m1');
    oldVideo = File('${tmp.path}/clips/0b5e.mp4');
    await oldVideo.writeAsBytes([1]);
    await prefs.setStringList('pending_removal_files', [oldVideo.path]);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// A fresh start, as main() builds it, then Settings > Recently deleted.
  Future<StorageService> openList(WidgetTester tester) async {
    final storage = StorageService(prefs);
    await tester.runAsync(() async {
      await storage.initialize();
      await storage.keepOldPendingFiles();
    });
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(OneSecondApp(
      storageService: storage,
      backupServiceFactory: () => BackupService(storage,
          vault: BackupVault(InMemoryVaultStore(),
              appId: 'punctum', extension: 'json'),
          prefs: prefs),
    ));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    final entry = find.text('Recently deleted');
    // The Settings list builds lazily: scroll to the entry, then bring it
    // fully on screen.
    await tester.scrollUntilVisible(entry, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(entry);
    await settle(tester);
    await tester.tap(entry);
    await settle(tester);
    return storage;
  }

  Finder row(String id) => find.byKey(ValueKey('deleted-$id'));
  Finder inRow(String id, String text) =>
      find.descendant(of: row(id), matching: find.text(text));
  const oldId = 'clip-file:0b5e';

  testWidgets('lists a pending clip, a pending montage and an old file',
      (tester) async {
    await openList(tester);

    expect(inRow('a', 'The clip for Sep 4, 2026'), findsOneWidget);
    expect(inRow('m1', 'The montage “Jul 1 - Jul 31, 2026”'), findsOneWidget);
    expect(inRow(oldId, 'A clip file kept from an older version'),
        findsOneWidget);

    expect(inRow('a', 'Restore'), findsOneWidget);
    expect(inRow('m1', 'Restore'), findsOneWidget);
    // Its day is not known for certain, so it cannot go back on one.
    expect(inRow(oldId, 'Restore'), findsNothing);
    expect(inRow(oldId, 'Keep'), findsOneWidget);
    for (final id in ['a', 'm1', oldId]) {
      expect(inRow(id, 'Delete for good'), findsOneWidget);
    }
  });

  testWidgets('Restore puts the clip back on its day', (tester) async {
    final storage = await openList(tester);

    await tester.tap(inRow('a', 'Restore'));
    await settle(tester);

    expect(storage.getClipsForDate('2026-09-04').map((c) => c.id), ['a']);
    expect(storage.pendingClipRemovals, isEmpty);
    expect(row('a'), findsNothing);
  });

  testWidgets('Restore puts the montage back on the list', (tester) async {
    final storage = await openList(tester);

    await tester.tap(inRow('m1', 'Restore'));
    await settle(tester);

    expect(storage.compilations.map((c) => c.id), ['m1']);
    expect(row('m1'), findsNothing);
  });

  testWidgets('Delete for good confirms first, naming the item, and only '
      'then removes the files', (tester) async {
    final storage = await openList(tester);

    await tester.tap(inRow('a', 'Delete for good'));
    await settle(tester);
    expect(find.text('Delete the clip for Sep 4, 2026 for good?'),
        findsOneWidget);
    expect(video.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(video.existsSync(), isTrue);
    expect(row('a'), findsOneWidget);

    await tester.tap(inRow('a', 'Delete for good'));
    await settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete for good')));
    await settle(tester);

    expect(video.existsSync(), isFalse);
    expect(thumb.existsSync(), isFalse);
    expect(storage.pendingClipRemovals, isEmpty);
    expect(row('a'), findsNothing);
  });

  testWidgets('Delete for good names the montage and the old file too',
      (tester) async {
    await openList(tester);

    await tester.tap(inRow('m1', 'Delete for good'));
    await settle(tester);
    expect(find.text('Delete the montage “Jul 1 - Jul 31, 2026” for good?'),
        findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete for good')));
    await settle(tester);
    expect(montage.existsSync(), isFalse);

    await tester.tap(inRow(oldId, 'Delete for good'));
    await settle(tester);
    expect(
        find.text('Delete a clip file kept from an older version for good?'),
        findsOneWidget);
    expect(oldVideo.existsSync(), isTrue);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete for good')));
    await settle(tester);
    expect(oldVideo.existsSync(), isFalse);
  });

  testWidgets('Keep leaves the old file and its entry', (tester) async {
    final storage = await openList(tester);

    await tester.tap(inRow(oldId, 'Keep'));
    await settle(tester);

    expect(oldVideo.existsSync(), isTrue);
    expect(storage.setAsideFiles.map((r) => r.id), [oldId]);
    expect(row(oldId), findsOneWidget);
  });

  testWidgets('the list does not overflow at 320dp and text scale 3.0',
      (tester) async {
    final storage = StorageService(prefs);
    await tester.runAsync(() async {
      await storage.initialize();
      await storage.keepOldPendingFiles();
    });
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 800);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(3.0)),
        child: child!,
      ),
      home: RecentlyDeletedScreen(storageService: storage),
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(row('a'), findsOneWidget);
  });
}
