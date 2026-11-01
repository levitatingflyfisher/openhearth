// The owner's ruling on the 30-day question (board-0167): "keep as built,
// ask once, Keep asks again in 30 days." This guards what was built
// (board-0124, board-0138): a deleted clip waits in Recently deleted; once
// it is more than 30 calendar days past its delete, the app asks once, at
// start; Keep leaves it and asks again 30 days later, not sooner and not
// never; the app never destroys anything on its own.
//
// Every video here is a made-up file of three bytes in a temporary folder.
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
  late DateTime now;

  const question =
      '1 deleted item is more than 30 days old. Delete it for good?';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_thirty_days_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'crt_effects': false,
    });
    prefs = await SharedPreferences.getInstance();
    video = File('${tmp.path}/clips/a.mp4');
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

  /// One made-up clip deleted at [deletedAt], by a run that has since
  /// stopped.
  Future<void> deleteAt(WidgetTester tester, DateTime deletedAt) async {
    await tester.runAsync(() async {
      final before = StorageService(prefs, clock: () => deletedAt);
      await before.initialize();
      await video.writeAsBytes([1, 2, 3]);
      await before.addClip(Clip(
        id: 'a',
        date: '2026-08-30',
        filePath: video.path,
        type: ClipType.video,
        createdAt: DateTime(2026, 8, 30),
      ));
      await before.removeClip('a');
    });
  }

  Widget app(StorageService storage) => OneSecondApp(
        storageService: storage,
        backupServiceFactory: () => BackupService(storage,
            vault: BackupVault(InMemoryVaultStore(),
                appId: 'punctum', extension: 'json'),
            prefs: prefs),
      );

  /// A fresh start at [now], as main() builds it.
  Future<StorageService> start(WidgetTester tester) async {
    final storage = StorageService(prefs, clock: () => now);
    await tester.runAsync(() async {
      await storage.initialize();
      await storage.keepOldPendingFiles();
    });
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(storage));
    await settle(tester);
    return storage;
  }

  /// The clip is still waiting in Recently deleted, file and entry.
  void expectStillKept(StorageService storage) {
    expect(storage.pendingClipRemovals.map((r) => r.id), ['a']);
    expect(video.existsSync(), isTrue);
    expect(video.readAsBytesSync(), [1, 2, 3]);
  }

  Future<void> keep(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Keep'));
    await settle(tester);
  }

  testWidgets('does not ask at exactly 30 days', (tester) async {
    await deleteAt(tester, DateTime(2026, 9, 1, 12));
    now = DateTime(2026, 10, 1, 12);
    final storage = await start(tester);

    expect(find.text(question), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expectStillKept(storage);
  });

  testWidgets('Keep asks again in 30 days: not sooner, and not never',
      (tester) async {
    await deleteAt(tester, DateTime(2026, 9, 1, 12));

    // Day 31: one ask.
    now = DateTime(2026, 10, 2, 9);
    var storage = await start(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(question), findsOneWidget);
    await keep(tester);
    expectStillKept(storage);

    // Later the same day, and 30 days after Keep: no ask.
    now = DateTime(2026, 10, 2, 20);
    storage = await start(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = DateTime(2026, 11, 1, 9);
    storage = await start(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expectStillKept(storage);

    // 31 days after Keep: one ask again.
    now = DateTime(2026, 11, 2, 9);
    storage = await start(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(question), findsOneWidget);
    await keep(tester);
    expectStillKept(storage);

    // And again 31 days after that second Keep.
    now = DateTime(2026, 12, 2, 9);
    storage = await start(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = DateTime(2026, 12, 3, 9);
    storage = await start(tester);
    expect(find.text(question), findsOneWidget);
    await keep(tester);
    expectStillKept(storage);
  });

  testWidgets('closing the question without a choice is a Keep',
      (tester) async {
    await deleteAt(tester, DateTime(2026, 9, 1, 12));
    now = DateTime(2026, 10, 2, 9);
    var storage = await start(tester);
    expect(find.text(question), findsOneWidget);

    // A tap outside the question closes it.
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expectStillKept(storage);

    now = DateTime(2026, 10, 3, 9);
    storage = await start(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = DateTime(2026, 11, 2, 9);
    storage = await start(tester);
    expect(find.text(question), findsOneWidget);
  });

  testWidgets('an unanswered question destroys nothing, however long it waits',
      (tester) async {
    await deleteAt(tester, DateTime(2026, 9, 1, 12));
    now = DateTime(2027, 10, 1, 9);
    final storage = await start(tester);
    expect(find.text(question), findsOneWidget);

    await tester.pump(const Duration(hours: 1));
    await settle(tester);

    expect(find.text(question), findsOneWidget);
    expectStillKept(storage);
  });

  test('starts without the calendar never destroy a deleted clip', () async {
    // What main() runs at every start, every 10 days for a year and a half.
    var day = DateTime(2026, 9, 1, 12);
    var storage = StorageService(prefs, clock: () => day);
    await storage.initialize();
    await video.writeAsBytes([1, 2, 3]);
    await storage.addClip(Clip(
      id: 'a',
      date: '2026-08-30',
      filePath: video.path,
      type: ClipType.video,
      createdAt: DateTime(2026, 8, 30),
    ));
    await storage.removeClip('a');

    for (var i = 0; i < 55; i++) {
      day = day.add(const Duration(days: 10));
      storage = StorageService(prefs, clock: () => day);
      await storage.initialize();
      await storage.keepOldPendingFiles();
      expectStillKept(storage);
    }
    expect(storage.oldRemovals.map((r) => r.id), ['a'],
        reason: 'it waits for the household to choose');
  });
}
