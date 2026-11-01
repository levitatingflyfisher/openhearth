import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The owner ruled (3 July 2026) that Android's own backup stays available:
/// the phone's owner decides in Android settings. A 27 July change turned it
/// off without that ruling; this pins the ruling back.
///
/// Static-content pin (same style as offline_fonts_test.dart). What must stay
/// out of Google backup is the key material, not the app: the recovery words
/// live in flutter_secure_storage, whose ciphertext sits in a shared-prefs
/// file that is useless without the Android keystore key, and which must not
/// be copied around.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const rulesPath = 'android/app/src/main/res/xml/data_extraction_rules.xml';
  const legacyPath = 'android/app/src/main/res/xml/backup_rules.xml';

  test('manifest leaves Android backup on and wires both rules files', () {
    final manifest = File(manifestPath).readAsStringSync();
    expect(manifest, contains('android:allowBackup="true"'),
        reason: 'the phone owner decides in Android settings (owner, 3 July)');
    expect(manifest, isNot(contains('android:allowBackup="false"')));
    expect(manifest, isNot(contains('android:fullBackupContent="false"')),
        reason: 'false would switch backup off on Android 11 and older');
    expect(manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
        manifest,
        contains(
            'android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'Android 12+ reads dataExtractionRules, not allowBackup alone');
  });

  for (final (name, path) in [
    ('extraction rules (Android 12+)', rulesPath),
    ('backup rules (Android 11 and older)', legacyPath),
  ]) {
    test('$name keep the database and exclude only the key files', () {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: 'the manifest names it');
      final rules = f.readAsStringSync();
      expect(
          RegExp(r'<exclude[^>]*domain="database"').hasMatch(rules), isFalse,
          reason: 'the saved places database is not excluded');
      expect(RegExp(r'<exclude\s+domain="(file|sharedpref|external)"\s*/>')
              .hasMatch(rules),
          isFalse,
          reason: 'no exclude-everything rule');
      // The recovery words: flutter_secure_storage keeps them in this file.
      expect(rules,
          contains('domain="sharedpref" path="FlutterSecureStorage.xml"'));
    });
  }

  test('extraction rules cover cloud backup and device transfer', () {
    final rules = File(rulesPath).readAsStringSync();
    expect(rules, contains('<cloud-backup'));
    expect(rules, contains('<device-transfer'));
    expect(
        RegExp('path="FlutterSecureStorage.xml"').allMatches(rules).length,
        greaterThanOrEqualTo(2),
        reason: 'key files stay out of BOTH cloud backup and transfer');
  });
}
