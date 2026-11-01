// A phone with no recovery words sets them up before its first backup,
// with the shared sheets every fleet app uses (sanctuary_backup_ui): the
// 12 words, then typed back from paper. Stopping at any point makes no
// backup and keeps no words: a locked file whose words were never written
// down could never be opened again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/screens/backup_restore_screen.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pt_words_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, InMemorySecureKeyStore keys) async {
    AppTheme.visualStyle = 'hearth';
    SharedPreferences.setMockInitialValues({'crt_effects': false});
    final svc = StorageService(await SharedPreferences.getInstance());
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      home: BackupRestoreScreen(storageService: svc, keyStore: keys),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool anyBackupFile() => tmp
      .listSync()
      .any((e) => e.path.contains('onesecond_backup_'));

  testWidgets('the first backup shows the 12 words before any file exists',
      (tester) async {
    final keys = InMemorySecureKeyStore();
    await pumpScreen(tester, keys);

    await tester.tap(find.text('CREATE BACKUP'));
    await tester.pumpAndSettle();

    expect(find.text('Your recovery words'), findsOneWidget);
    expect(anyBackupFile(), isFalse);
  });

  testWidgets('"Not now" makes no backup and keeps no words', (tester) async {
    final keys = InMemorySecureKeyStore();
    await pumpScreen(tester, keys);

    await tester.tap(find.text('CREATE BACKUP'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Your recovery words'), findsNothing);
    expect(await keys.readMnemonic(), isNull);
    expect(anyBackupFile(), isFalse);
  });

  testWidgets('words that were written down but not typed back are not kept',
      (tester) async {
    final keys = InMemorySecureKeyStore();
    await pumpScreen(tester, keys);

    await tester.tap(find.text('CREATE BACKUP'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("I've written this down"));
    await tester.tap(find.text("I've written this down"));
    await tester.pumpAndSettle();

    // The shared check asks for the words from paper; cancel it.
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    expect(cancel, findsWidgets);
    await tester.tap(cancel.first);
    await tester.pumpAndSettle();

    expect(await keys.readMnemonic(), isNull);
    expect(anyBackupFile(), isFalse);
  });
}
