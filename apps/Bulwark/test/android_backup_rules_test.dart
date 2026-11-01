import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The recovery words and device id live in flutter_secure_storage's
/// SharedPreferences file. Android's own backup to Google must never carry it,
/// whether the phone owner has that backup on or not. The rest of the app data
/// stays in backup.
const _secretFile = 'FlutterSecureStorage.xml';

String _read(String path) => File(path).readAsStringSync();

String _section(String xml, String tag) {
  final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  expect(match, isNotNull, reason: 'missing <$tag>');
  return match!.group(1)!;
}

final _secretExclude = RegExp(
  '<exclude\\s+domain="sharedpref"\\s+path="$_secretFile"\\s*/>',
);

void main() {
  const res = 'android/app/src/main/res/xml';

  test('the manifest names both backup rules files', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('Android 12 and newer: cloud backup and device transfer skip the secret file',
      () {
    final xml = _read('$res/data_extraction_rules.xml');
    expect(_section(xml, 'cloud-backup'), matches(_secretExclude));
    expect(_section(xml, 'device-transfer'), matches(_secretExclude));
  });

  test('Android 11 and older: full backup skips the secret file', () {
    final xml = _read('$res/backup_rules.xml');
    expect(_section(xml, 'full-backup-content'), matches(_secretExclude));
  });

  test('the rules exclude only the secret file', () {
    for (final name in ['data_extraction_rules.xml', 'backup_rules.xml']) {
      final xml = _read('$res/$name');
      expect(RegExp('<exclude ').allMatches(xml).length,
          name == 'backup_rules.xml' ? 1 : 2,
          reason: name);
      expect(xml, isNot(contains('<include')), reason: name);
    }
  });
}
