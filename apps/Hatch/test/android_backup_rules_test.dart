import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys and recovery words stay out of Android's backup to Google.
///
/// sanctuary_auth_core keeps the recovery words (and the key made from them)
/// with flutter_secure_storage, which writes
/// shared_prefs/FlutterSecureStorage.xml. The manifest leaves Android backup
/// at its default, so the phone's owner may turn it on; these rules keep that
/// one file out of it, and out of device transfer. Nothing else is excluded.
void main() {
  const secretFile = 'FlutterSecureStorage.xml';
  const excludeTag = '<exclude domain="sharedpref" path="$secretFile"';

  String read(String path) => File(path).readAsStringSync();

  final manifest = read('android/app/src/main/AndroidManifest.xml');

  test('the manifest names both rules files and leaves allowBackup alone', () {
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest, isNot(contains('android:allowBackup')));
  });

  test('Android 12 and newer: cloud backup and device transfer skip the secrets', () {
    final rules = read('android/app/src/main/res/xml/data_extraction_rules.xml');
    for (final section in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$section>(.*?)</$section>', dotAll: true)
          .firstMatch(rules);
      expect(block, isNotNull, reason: '$section block is missing');
      expect(block!.group(1), contains(excludeTag));
    }
  });

  test('Android 11 and older: full backup skips the secrets', () {
    final rules = read('android/app/src/main/res/xml/backup_rules.xml');
    final block = RegExp('<full-backup-content>(.*?)</full-backup-content>',
            dotAll: true)
        .firstMatch(rules);
    expect(block, isNotNull);
    expect(block!.group(1), contains(excludeTag));
  });

  test('the rules exclude only the secret file', () {
    for (final name in ['data_extraction_rules.xml', 'backup_rules.xml']) {
      final rules = read('android/app/src/main/res/xml/$name')
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final excluded = RegExp(r'<exclude\b[^>]*>').allMatches(rules);
      for (final m in excluded) {
        expect(m.group(0), contains('path="$secretFile"'), reason: name);
      }
    }
  });
}
