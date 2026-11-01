import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android's own backup to Google stays the phone owner's option, so the
/// manifest leaves allowBackup alone. The encrypted backup's recovery words
/// live in flutter_secure_storage's FlutterSecureStorage.xml (the default
/// file name; sanctuary_auth_core sets no other). A copy of it must not ride
/// into a Google backup or a device transfer.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  String rules(String name) =>
      File('android/app/src/main/res/xml/$name.xml').readAsStringSync();

  test('manifest points both backup rule attributes at rule files', () {
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('manifest leaves allowBackup alone', () {
    expect(manifest, isNot(contains('android:allowBackup')));
  });

  test('data_extraction_rules excludes the secret file from cloud backup', () {
    final text = rules('data_extraction_rules');
    final cloud = RegExp(r'<cloud-backup>([\s\S]*?)</cloud-backup>')
        .firstMatch(text);
    expect(cloud, isNotNull);
    expect(cloud!.group(1),
        contains('<exclude domain="sharedpref" path="FlutterSecureStorage.xml"'));
  });

  test('data_extraction_rules excludes the secret file from device transfer',
      () {
    final text = rules('data_extraction_rules');
    final transfer = RegExp(r'<device-transfer>([\s\S]*?)</device-transfer>')
        .firstMatch(text);
    expect(transfer, isNotNull);
    expect(transfer!.group(1),
        contains('<exclude domain="sharedpref" path="FlutterSecureStorage.xml"'));
  });

  test('backup_rules excludes the secret file from full backup', () {
    final text = rules('backup_rules');
    expect(text, contains('<full-backup-content>'));
    expect(text,
        contains('<exclude domain="sharedpref" path="FlutterSecureStorage.xml"'));
  });

  test('the rules exclude nothing else', () {
    for (final name in ['data_extraction_rules', 'backup_rules']) {
      final excludes =
          RegExp(r'<exclude [^>]*>').allMatches(rules(name)).length;
      expect(excludes, name == 'backup_rules' ? 1 : 2, reason: name);
    }
  });
}
