// The backup is locked with the household's 12 recovery words (OHBS, see
// lib/services/backup_stream_cipher.dart). The screen says so above the
// button, before the file exists: what the file holds, that the words are
// what opens it, and that without them nobody can, the owner included.
// (Before this the line said the ZIP was not password-protected: lens
// audit writing-is-designing-03, finding 11; persona G5.)
//
// Each content claim is checked against what BackupService.createBackup
// packs: clips/ and thumbnails/, metadata.json (dates, tags, place names
// and coordinates, names from face recognition), faces/ (the named face
// crops), settings.json, and compilations/ when montages are included.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/screens/backup_restore_screen.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the notice says the words lock it and names what is inside', () {
    const n = BackupRestoreScreen.backupFileNotice;
    for (final claim in [
      'locked with your 12 recovery words',
      'clips',
      'dates',
      'places',
      'tags',
      'names and face pictures',
      'Without the words nobody can open it, you included',
      'keep them on paper',
    ]) {
      expect(n, contains(claim), reason: claim);
    }
    // It is no longer a plain ZIP, so the old line must not come back.
    expect(n, isNot(contains('isn’t password-protected')));
  });

  testWidgets('it is on the screen, above Create Backup', (tester) async {
    AppTheme.visualStyle = 'hearth';
    SharedPreferences.setMockInitialValues({'crt_effects': false});
    final svc = StorageService(await SharedPreferences.getInstance());
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      home: BackupRestoreScreen(
          storageService: svc, keyStore: InMemorySecureKeyStore()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final notice = find.text(BackupRestoreScreen.backupFileNotice);
    expect(notice, findsOneWidget);
    expect(tester.getTopLeft(notice).dy,
        lessThan(tester.getTopLeft(find.text('CREATE BACKUP')).dy));
  });
}
