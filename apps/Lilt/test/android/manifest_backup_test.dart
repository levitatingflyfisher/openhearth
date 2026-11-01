import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Config guard for the Android backup rules.
///
/// Android's own backup to Google stays the phone owner's choice, so
/// `allowBackup` is not turned off here. The encrypted recovery words live in
/// flutter_secure_storage's shared-preferences file (via sanctuary_auth_core),
/// and that file must never go into Google backup or a device transfer.
/// This reads the files, since Auto Backup cannot run under `flutter test`.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const extractionPath =
      'android/app/src/main/res/xml/data_extraction_rules.xml';
  const fullBackupPath = 'android/app/src/main/res/xml/backup_rules.xml';
  const exclusion =
      '<exclude domain="sharedpref" path="FlutterSecureStorage.xml" />';

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue,
        reason: '$path is missing; the manifest needs it to build.');
    return file.readAsStringSync();
  }

  test('manifest names both rules files and leaves backup allowed', () {
    final manifest = read(manifestPath);

    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'Android 12 and newer read this file.');
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'Android 11 and older read this file.');
    expect(manifest, isNot(contains('android:allowBackup="false"')),
        reason: 'Backup to Google is the phone owner\'s choice.');
  });

  test('cloud backup and device transfer both exclude the secret file', () {
    final rules = read(extractionPath);
    final cloud = RegExp(r'<cloud-backup[^>]*>([\s\S]*?)</cloud-backup>')
        .firstMatch(rules);
    final transfer = RegExp(r'<device-transfer[^>]*>([\s\S]*?)</device-transfer>')
        .firstMatch(rules);

    expect(cloud, isNotNull);
    expect(transfer, isNotNull);
    expect(cloud!.group(1), contains(exclusion));
    expect(transfer!.group(1), contains(exclusion));
  });

  test('full backup rules exclude the secret file', () {
    expect(read(fullBackupPath), contains(exclusion));
  });

  test('the rules exclude nothing else', () {
    for (final path in [extractionPath, fullBackupPath]) {
      final rules = read(path);
      final excludes = RegExp(r'<exclude\b[^>]*>').allMatches(rules);
      for (final m in excludes) {
        expect(m.group(0), exclusion, reason: '$path excludes more than the '
            'recovery words file.');
      }
    }
  });
}
