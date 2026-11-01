// A restore must leave nothing old in memory and no old write waiting
// (fleet erase and restore audit, 12 November 2026).
//
// Before: both restore paths reloaded the journal with
// StorageService.initialize(), which never moved the `changes` notifier.
// The calendar and the day view sit under Settings during a restore and
// kept drawing the old journal. The app-wide Undo bar outlived the restore:
// a pending "Deleted the clip" offer put the old clip into the restored
// journal. Settings, the app's theme and the daily reminder kept the
// settings from before the restore.
//
// After: both paths call StorageService.reload(), the one reset path. It
// re-reads metadata.json, then moves `reloads` and `changes`. The app ends
// the Undo offer (cancelled: neither undone nor committed, so the clip stays
// in Recently deleted) and re-reads its settings; Settings re-reads its own.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/screens/day_view_screen.dart';
import 'package:one_second_a_day/screens/settings_screen.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:one_second_a_day/widgets/undo_host.dart';
import 'package:one_second_a_day/widgets/crt_effects.dart';
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

/// The two ways a restore replaces the journal: a backup file and a
/// rollback to a vault snapshot.
enum _Path { backup, snapshot }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late SharedPreferences prefs;
  late StorageService storage;
  late BackupVault vault;
  final day = DateTime(2026, 9, 4);

  BackupService service() => BackupService(storage, vault: vault, prefs: prefs);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_restore_reset_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'crt_effects': false,
      'theme_mode': 1,
    });
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    await storage.initialize();
    vault =
        BackupVault(InMemoryVaultStore(), appId: 'punctum', extension: 'json');
  });

  tearDown(() async {
    AppTheme.visualStyle = 'hearth';
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Clip clipFor(String id) => Clip(
        id: id,
        date: '2026-09-04',
        // A path that does not exist keeps video_player out of the test.
        filePath: '${tmp.path}/clips/$id-absent.mp4',
        type: ClipType.video,
        createdAt: day,
      );

  Uint8List zipOf(Map<String, dynamic> metadata,
      {Map<String, dynamic>? settings}) {
    final archive = Archive();
    final bytes = utf8.encode(jsonEncode(metadata));
    archive.addFile(ArchiveFile('metadata.json', bytes.length, bytes));
    if (settings != null) {
      final s = utf8.encode(jsonEncode(settings));
      archive.addFile(ArchiveFile('settings.json', s.length, s));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  final emptyJournal = <String, dynamic>{
    'clips': <String, dynamic>{},
    'compilations': <dynamic>[],
  };

  /// Replaces the journal by [path] with an empty one carrying [settings].
  /// The snapshot is built from the same metadata and settings, so both
  /// paths restore the same thing.
  Future<void> restore(_Path path, {Map<String, dynamic>? settings}) async {
    final svc = service();
    switch (path) {
      case _Path.backup:
        await svc.restoreBackup(zipOf(emptyJournal, settings: settings), (_) {},
            replace: true);
      case _Path.snapshot:
        final entry = await vault.save(
          // The v2 composite shape, which the serializer reads forever.
          Uint8List.fromList(utf8.encode(jsonEncode({
            'snapshotVersion': 2,
            'metadata': emptyJournal,
            'settings': settings ?? <String, dynamic>{},
          }))),
          label: VaultLabel.manual,
        );
        await svc.restoreMetadataSnapshot(entry.id, (_) {});
    }
  }

  Future<void> settle(WidgetTester tester) async {
    // Real file I/O needs a real event loop, which testWidgets' fake clock
    // does not turn; loop enough times for a write and a route to finish.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  final reminderCalls = <(bool, TimeOfDay)>[];

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    reminderCalls.clear();
    await tester.pumpWidget(OneSecondApp(
      storageService: storage,
      backupServiceFactory: () => BackupService(storage,
          vault: BackupVault(InMemoryVaultStore(),
              appId: 'punctum', extension: 'json'),
          prefs: prefs),
      syncReminder: (enabled, time) async => reminderCalls.add((enabled, time)),
    ));
    await settle(tester);
  }

  Future<void> openDay(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => DayViewScreen(
              storageService: storage,
              initialDate: day,
              onDelete: () {},
            ),
          ),
        );
    await settle(tester);
  }

  for (final path in _Path.values) {
    group('after a ${path.name} restore', () {
      test('the screens are told: `changes` moves', () async {
        await storage.addClip(clipFor('old'));
        var told = 0;
        void listener() => told++;
        storage.changes.addListener(listener);
        addTearDown(() => storage.changes.removeListener(listener));

        await restore(path);

        expect(storage.hasClipForDate('2026-09-04'), isFalse);
        expect(told, greaterThan(0),
            reason: 'the calendar and the day view redraw only on changes');
      });

      testWidgets('the day view under it shows the restored journal',
          (tester) async {
        await tester.runAsync(() => storage.addClip(clipFor('old')));
        await pumpApp(tester);
        await openDay(tester);
        expect(find.byTooltip('Delete clip'), findsWidgets);

        await tester.runAsync(() => restore(path));
        await settle(tester);

        expect(find.byTooltip('Delete clip'), findsNothing,
            reason: 'the restored journal has no clip on this day');
      });

      testWidgets(
          'a pending Undo is ended and cannot put the old clip into the '
          'restored journal; the clip stays in Recently deleted',
          (tester) async {
        await tester.runAsync(() => storage.addClip(clipFor('old')));
        await pumpApp(tester);
        await openDay(tester);
        await tester.tap(find.byTooltip('Delete clip').first);
        await settle(tester);
        expect(find.text('Undo'), findsOneWidget);

        await tester.runAsync(() => restore(path));
        await settle(tester);

        expect(find.text('Undo'), findsNothing);
        expect(storage.hasClipForDate('2026-09-04'), isFalse);
        // Ending the offer never destroys: the clip and its row wait in
        // Recently deleted, as after a dismissed bar.
        expect(storage.pendingClipRemovals.map((r) => r.clip.id), ['old']);
      });

      testWidgets(
          'a restore ends a pending Undo without running its onCommit',
          (tester) async {
        await pumpApp(tester);
        // The app's own controller, as the Undo bar reads it. No screen in
        // PT passes an onCommit, so the test gives the offer one.
        final undo = tester.widget<UndoHost>(find.byType(UndoHost)).controller;
        var committed = false;
        undo.show(
          message: 'Deleted the clip',
          onUndo: () async {},
          onCommit: () async => committed = true,
        );
        await settle(tester);
        expect(find.text('Undo'), findsOneWidget);

        await tester.runAsync(() => restore(path));
        await settle(tester);

        expect(find.text('Undo'), findsNothing);
        expect(committed, isFalse,
            reason: 'a commit is written against the journal from before');
      });

      testWidgets('the app takes the restored theme and style at once',
          (tester) async {
        await pumpApp(tester);
        expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
            ThemeMode.light);

        await tester.runAsync(() => restore(path, settings: {
              'theme_mode': 0,
              'visual_style': 'retro',
            }));
        await settle(tester);

        expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
            ThemeMode.dark);
        expect(AppTheme.visualStyle, 'retro');
      });

      testWidgets('the daily reminder follows the restored setting',
          (tester) async {
        await pumpApp(tester);

        await tester.runAsync(() => restore(path, settings: {
              'reminder_enabled': true,
              'reminder_time': '07:15',
            }));
        await settle(tester);

        expect(reminderCalls, [(true, const TimeOfDay(hour: 7, minute: 15))]);
      });

      testWidgets('Settings under the restore shows the restored settings',
          (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: SettingsScreen(
            storageService: storage,
            onThemeChanged: (_, __) {},
          ),
        ));
        await settle(tester);
        expect(tester.widget<CrtOverlay>(find.byType(CrtOverlay)).enabled,
            isFalse);

        await tester
            .runAsync(() => restore(path, settings: {'crt_effects': true}));
        await settle(tester);

        expect(
            tester.widget<CrtOverlay>(find.byType(CrtOverlay)).enabled, isTrue);
      });
    });
  }
}
