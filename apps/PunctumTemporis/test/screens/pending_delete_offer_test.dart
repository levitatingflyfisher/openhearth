// A deleted clip waits, files and row, until its owner chooses (owner
// ruling, board-0124: "keep the deleted clip's file and offer Undo at the
// next start; a clip is destroyed only after the owner really confirms").
//
// Before: a kill with the Undo bar on screen destroyed the clip's files at
// the next start, with no question. Now the next start says on the
// calendar how many deleted items are kept, and points to Recently deleted
// (board-0138), where each has Restore and a confirmed "Delete for good".
// Closing the note leaves them pending and it shows again at the next
// start.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
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
  late SharedPreferences prefs;
  late File video;
  late File thumb;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_pending_delete_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'crt_effects': false,
    });
    prefs = await SharedPreferences.getInstance();
    // The run before the kill: one clip, deleted, Undo still on screen.
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

  /// A fresh start: a new storage over the same disk, as main() builds it.
  Future<StorageService> start(WidgetTester tester) async {
    final storage = StorageService(prefs);
    await tester.runAsync(() async {
      await storage.initialize();
      await storage.keepOldPendingFiles();
    });
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // A new tree, so the calendar's state starts over like a real start.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(OneSecondApp(
      storageService: storage,
      backupServiceFactory: () => BackupService(storage,
          vault: BackupVault(InMemoryVaultStore(),
              appId: 'punctum', extension: 'json'),
          prefs: prefs),
    ));
    await settle(tester);
    return storage;
  }

  const note = '1 deleted item is kept until you choose.';

  testWidgets('the next start says the deleted clip is kept', (tester) async {
    await start(tester);

    expect(find.text(note), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Recently deleted'),
        findsOneWidget);
  });

  testWidgets('the note opens Recently deleted, where Restore puts the clip '
      'back on its day', (tester) async {
    final storage = await start(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Recently deleted'));
    await settle(tester);
    expect(find.text('The clip for Sep 4, 2026'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await settle(tester);
    expect(storage.getClipsForDate('2026-09-04').map((c) => c.id), ['a']);
    expect(storage.pendingClipRemovals, isEmpty);

    await tester.pageBack();
    await settle(tester);
    expect(find.text(note), findsNothing);
  });

  testWidgets('closing the note keeps the clip pending and shows it again',
      (tester) async {
    final storage = await start(tester);

    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    expect(find.text(note), findsNothing);
    expect(storage.pendingClipRemovals, hasLength(1));
    expect(video.existsSync(), isTrue);
    expect(thumb.existsSync(), isTrue);

    await start(tester);
    expect(find.text(note), findsOneWidget);
  });
}
