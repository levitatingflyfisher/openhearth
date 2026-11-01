// The "Include montage videos" toggle on the backup screen: ON by default
// (montages are the point of the app), persisted, and honored end-to-end —
// flipping it off must actually keep montage MP4s out of the created ZIP,
// not just flip a switch.
//
// Widget-test discipline: real filesystem work (seeding, and taps that
// drive the zip encode) runs inside tester.runAsync — real I/O never
// completes under the fake async zone and hangs pumpAndSettle.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show OpenHearthMnemonic;
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/screens/backup_restore_screen.dart';
import 'package:one_second_a_day/services/backup_key.dart';
import 'package:one_second_a_day/services/backup_stream_cipher.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';

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
  late StorageService svc;

  setUp(() {
    AppTheme.visualStyle = 'retro';
    tmp = Directory.systemTemp.createTempSync('pt_toggle_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.buildTheme(Brightness.dark, Colors.green),
        home: child,
      );

  Future<void> seed(WidgetTester tester, {bool withMontage = false}) async {
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      svc = StorageService(prefs);
      await svc.initialize();
      if (withMontage) {
        final path = '${tmp.path}/compiled/jul.mp4';
        await File(path).parent.create(recursive: true);
        await File(path).writeAsBytes(List<int>.filled(64, 7));
        await svc.addCompilation(Compilation(
          id: 'jul',
          title: 'jul',
          filePath: path,
          clipIds: const [],
          createdAt: DateTime(2026, 7, 1),
        ));
      }
    });
  }

  Future<Archive> createBackupViaUi(WidgetTester tester) async {
    // A phone that already has its recovery words: the backup goes straight
    // to the locked file, and the test opens it with the same words.
    final phrase = OpenHearthMnemonic.generate();
    final keys = InMemorySecureKeyStore();
    await tester.runAsync(() => keys.writeMnemonic(phrase));
    await tester.pumpWidget(
        wrap(BackupRestoreScreen(storageService: svc, keyStore: keys)));
    await tester.pumpAndSettle();

    late Archive archive;
    await tester.runAsync(() async {
      await tester.tap(find.text('CREATE BACKUP'));
      // Deriving the key, the ZIP, sealing and the chunk-by-chunk read-back
      // are real work: wait until the finished file is there and its
      // unsealed .part is gone.
      List<File> backups() => tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('onesecond_backup_'))
          .toList();
      for (var i = 0; i < 200; i++) {
        final files = backups();
        if (files.length == 1 && !files.single.path.endsWith('.part')) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final files = backups();
      expect(files, hasLength(1), reason: 'the backup file must exist');
      expect(files.single.path, endsWith('.ohbs'));
      final words = await BackupKey.fromPhrase(phrase);
      final zip = BytesBuilder(copy: false);
      await for (final part in BackupStreamCipher.decrypt(
          files.single.openRead(), words)) {
        zip.add(part);
      }
      archive = ZipDecoder().decodeBytes(zip.toBytes());
    });
    await tester.pumpAndSettle();
    return archive;
  }

  group('StorageService include-montages pref', () {
    test('defaults to true and persists a change', () async {
      final prefs = await SharedPreferences.getInstance();
      svc = StorageService(prefs);
      expect(svc.getIncludeMontagesInBackup(), isTrue,
          reason: 'montages are the point — carrying them is the default');
      await svc.setIncludeMontagesInBackup(false);
      expect(svc.getIncludeMontagesInBackup(), isFalse);
    });
  });

  group('backup screen toggle', () {
    testWidgets('renders ON by default and persists when flipped',
        (tester) async {
      await seed(tester);
      await tester.pumpWidget(wrap(BackupRestoreScreen(storageService: svc)));
      await tester.pumpAndSettle();

      expect(find.text('Include montage videos'), findsOneWidget);
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(svc.getIncludeMontagesInBackup(), isFalse);
    });

    testWidgets('toggle OFF keeps montage files out of the created ZIP',
        (tester) async {
      await seed(tester, withMontage: true);
      await tester.runAsync(() => svc.setIncludeMontagesInBackup(false));

      final archive = await createBackupViaUi(tester);
      expect(
          archive
              .map((e) => e.name)
              .where((n) => n.startsWith('compilations/')),
          isEmpty,
          reason: 'the flipped-off toggle must reach createBackup');
    });

    testWidgets('toggle ON (default) carries montage files in the ZIP',
        (tester) async {
      await seed(tester, withMontage: true);

      final archive = await createBackupViaUi(tester);
      expect(archive.map((e) => e.name), contains('compilations/jul.mp4'));
    });
  });
}
