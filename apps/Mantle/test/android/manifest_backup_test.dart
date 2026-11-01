import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Config-guard for the Android backup posture.
///
/// The owner ruled that Android's own backup stays on, and that the phone's
/// owner decides through Android settings. A July change turned it off in the
/// manifest and excluded everything in the rules. This pins the ruling back:
/// Auto Backup is allowed, the journaling database is not excluded, and the
/// recovery words never go into Google backup.
///
/// This is a file-content guard (an Auto-Backup behavioral test is not
/// runnable under `flutter test`).
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const extractionPath =
      'android/app/src/main/res/xml/data_extraction_rules.xml';
  const fullBackupPath = 'android/app/src/main/res/xml/backup_rules.xml';

  test('manifest allows Android backup', () {
    final manifest = File(manifestPath).readAsStringSync();

    expect(manifest, contains('android:allowBackup="true"'),
        reason: 'The owner ruled Android backup is the phone owner\'s choice.');
    expect(manifest, isNot(contains('android:allowBackup="false"')));
    expect(manifest, isNot(contains('android:fullBackupContent="false"')));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      reason: 'Android 12+ reads dataExtractionRules; it keeps the recovery '
          'words out of the backup.',
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'Older phones read fullBackupContent for the same exclusion.');
  });

  for (final path in [extractionPath, fullBackupPath]) {
    test('$path keeps the database in and the recovery words out', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'The manifest references this resource; the build breaks '
              'without it.');
      final rules = file.readAsStringSync();

      expect(rules, isNot(contains('<exclude domain="root"')),
          reason: 'Excluding root drops everything, which is the July change.');
      expect(rules, isNot(contains('<exclude domain="database"')),
          reason: 'The app\'s database is the data the owner wants backed up.');
      expect(rules, isNot(contains('<exclude domain="file" path="."')));
      expect(rules, isNot(contains('<exclude domain="sharedpref" path="."')));
      expect(rules, contains('FlutterSecureStorage.xml'),
          reason: 'flutter_secure_storage keeps the recovery words here. They '
              'must not go into Google backup.');
      expect(rules, isNot(contains('disableIfNoEncryptionCapabilities')));
    });
  }

  test('data_extraction_rules.xml covers cloud backup and device transfer',
      () {
    final rules = File(extractionPath).readAsStringSync();
    expect(rules, contains('<cloud-backup'));
    expect(rules, contains('<device-transfer'));
  });
}
