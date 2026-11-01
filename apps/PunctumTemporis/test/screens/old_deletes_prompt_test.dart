// The 30-day question (owner rulings, board-0138 and board-0167, which
// kept it as built): nothing deleted is destroyed
// on a timer, because a clip goes only after its owner really confirms.
// Instead, once an item is more than 30 days past its delete, the app asks
// once, at start, with Delete for good and Keep. Keep leaves the items and
// their files, and the question comes back 30 days later.
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
    tmp = await Directory.systemTemp.createTemp('pt_old_deletes_');
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

  /// One clip deleted at [deletedAt], by a run that has since stopped.
  Future<void> deleteAt(WidgetTester tester, DateTime deletedAt) async {
    await tester.runAsync(() async {
      final before = StorageService(prefs, clock: () => deletedAt);
      await before.initialize();
      await video.writeAsBytes([1, 2, 3]);
      await before.addClip(Clip(
        id: 'a',
        date: '2026-09-04',
        filePath: video.path,
        type: ClipType.video,
        createdAt: DateTime(2026, 9, 4),
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

  testWidgets(
      'asks once for an item 31 days old across a clock change, and Keep '
      'leaves it and its files', (tester) async {
    // Deleted late on Oct 15; the start is just after midnight on Nov 15,
    // 31 calendar days on with the Nov 1 clock change in between.
    await deleteAt(tester, DateTime(2026, 10, 15, 23, 30));
    now = DateTime(2026, 11, 15, 0, 10);
    final storage = await start(tester);

    expect(find.text(question), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Keep'), findsOneWidget);
    expect(find.text('Delete for good'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Keep'));
    await settle(tester);

    expect(find.text(question), findsNothing);
    expect(storage.pendingClipRemovals.map((r) => r.id), ['a']);
    expect(video.existsSync(), isTrue);

    // Once: not again in this run, and not at the next start.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(storage));
    await settle(tester);
    expect(find.text(question), findsNothing);
    await start(tester);
    expect(find.text(question), findsNothing);
  });

  testWidgets('does not ask for an item 29 days old', (tester) async {
    await deleteAt(tester, DateTime(2026, 10, 17, 0, 10));
    now = DateTime(2026, 11, 15, 0, 10);
    await start(tester);

    expect(find.text(question), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Delete for good in the question destroys the old item',
      (tester) async {
    await deleteAt(tester, DateTime(2026, 9, 1, 12));
    now = DateTime(2026, 10, 15, 12);
    final storage = await start(tester);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete for good')));
    await settle(tester);

    expect(video.existsSync(), isFalse);
    expect(storage.pendingClipRemovals, isEmpty);
  });
}
