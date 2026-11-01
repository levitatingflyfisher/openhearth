// Android's own backup to Google is on for this app (the manifest leaves
// allowBackup at its default). Android skips an app whose data is large,
// which video journals are, so the screen says so and points at the one
// copy that holds the clips. Each claim is checked against
// BackupService.createBackup: every clip with a readable file goes into
// the backup, and montage videos go in only while the "Include montage
// videos" switch is on (it starts on). Android's copy is Android's, not
// the locked file, so these two lines must not call it private or
// encrypted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/screens/backup_restore_screen.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the two lines say what Android does and what the ZIP holds', () {
    const google = BackupRestoreScreen.googleBackupNotice;
    const large = BackupRestoreScreen.largeBackupNotice;
    expect(
        google, contains('Android may also back up this app’s data to Google'));
    expect(
        google, contains('if the phone’s owner allows it in Android settings'));
    expect(large,
        contains('Android skips its own backup of an app whose data is large'));
    expect(large, contains('photos and video may not be in it'));
    expect(large, contains('The backup here holds your clips'));
    expect(large, contains('montage videos if the switch above is on'));
    // These lines are about Android's copy, which PT does not lock.
    for (final s in [google, large]) {
      expect(s.toLowerCase(), isNot(contains('encrypted')));
      expect(s.toLowerCase(), isNot(contains('private choice')));
      expect(s.toLowerCase(), isNot(contains('always holds everything')));
    }
  });

  testWidgets(
      'both lines are on the screen, below the file notice and above Create Backup',
      (tester) async {
    AppTheme.visualStyle = 'hearth';
    SharedPreferences.setMockInitialValues({'crt_effects': false});
    final svc = StorageService(await SharedPreferences.getInstance());
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      home: BackupRestoreScreen(storageService: svc),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final zip = find.text(BackupRestoreScreen.backupFileNotice);
    final google = find.text(BackupRestoreScreen.googleBackupNotice);
    final large = find.text(BackupRestoreScreen.largeBackupNotice);
    final create = find.text('CREATE BACKUP');
    expect(google, findsOneWidget);
    expect(large, findsOneWidget);
    expect(
        tester.getTopLeft(google).dy, greaterThan(tester.getTopLeft(zip).dy));
    expect(
        tester.getTopLeft(large).dy, greaterThan(tester.getTopLeft(google).dy));
    expect(tester.getTopLeft(large).dy, lessThan(tester.getTopLeft(create).dy));
  });
}
