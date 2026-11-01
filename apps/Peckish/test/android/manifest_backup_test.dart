import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Config-guard for the Android backup posture.
///
/// The owner ruled that Android's own backup stays the phone owner's choice.
/// Peckish keeps its sync secret, its stove phrase and the Anthropic key in
/// flutter_secure_storage, which writes shared_prefs/FlutterSecureStorage.xml.
/// That file must never go to Google backup or a device transfer. Nothing else
/// is excluded: the recipe box and diary are the data the owner wants backed up.
///
/// This is a file-content guard (an Auto-Backup behavioural test is not
/// runnable under `flutter test`).
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const extractionPath =
      'android/app/src/main/res/xml/data_extraction_rules.xml';
  const fullBackupPath = 'android/app/src/main/res/xml/backup_rules.xml';

  test('manifest keeps Android backup allowed and names both rules files', () {
    final manifest = File(manifestPath).readAsStringSync();

    expect(manifest, isNot(contains('android:allowBackup="false"')));
    expect(manifest, isNot(contains('android:fullBackupContent="false"')));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      reason: 'Android 12+ reads dataExtractionRules.',
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'Android 11 and older read fullBackupContent.');
  });

  for (final path in [extractionPath, fullBackupPath]) {
    test('$path leaves out the secret file and nothing else', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'The manifest references this resource; the build breaks '
              'without it.');
      final rules = file.readAsStringSync();

      expect(rules, contains('<exclude domain="sharedpref" '
          'path="FlutterSecureStorage.xml" />'),
          reason: 'flutter_secure_storage keeps the sync secret, the stove '
              'phrase and the Anthropic key here.');
      expect(rules, isNot(contains('<exclude domain="root"')));
      expect(rules, isNot(contains('<exclude domain="database"')));
      expect(rules, isNot(contains('<exclude domain="file"')));
      expect(rules, isNot(contains('<exclude domain="external"')));
      expect(rules, isNot(contains('path="."')));
      expect(rules, isNot(contains('disableIfNoEncryptionCapabilities')));
    });
  }

  test('data_extraction_rules.xml covers cloud backup and device transfer', () {
    final rules = File(extractionPath).readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final start = rules.indexOf('<$section>');
      final end = rules.indexOf('</$section>');
      expect(start, greaterThanOrEqualTo(0), reason: 'missing <$section>');
      expect(end, greaterThan(start));
      expect(rules.substring(start, end), contains('FlutterSecureStorage.xml'),
          reason: '<$section> must exclude the secret file itself.');
    }
  });
}
