import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app leaves Android's own backup on (the default), so the manifest has
/// to say what stays out of it. flutter_secure_storage keeps the recovery
/// words and the WebDAV password in FlutterSecureStorage.xml; a copy of that
/// file on another phone is useless, and no copy should leave this one.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('manifest points both backup rule attributes at rule files', () {
    expect(manifest, contains('android:dataExtractionRules='
        '"@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent='
        '"@xml/backup_rules"'));
    expect(manifest, isNot(contains('android:allowBackup="false"')));
  });

  for (final name in ['data_extraction_rules', 'backup_rules']) {
    test('$name keeps FlutterSecureStorage.xml out of Google backup', () {
      final rules =
          File('android/app/src/main/res/xml/$name.xml').readAsStringSync();
      expect(rules, contains('domain="sharedpref"'));
      expect(rules, contains('path="FlutterSecureStorage.xml"'));
    });
  }

  test('data_extraction_rules covers cloud backup and device transfer', () {
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
  });
}
