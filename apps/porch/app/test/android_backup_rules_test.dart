// Android's own backup to Google is the phone owner's choice. Two things
// must never ride in it:
// - the keys and the identity words: flutter_secure_storage (with
//   encryptedSharedPreferences) keeps porch.entropy.v1 and
//   porch.statekey.v1 in shared_prefs/FlutterSecureStorage.xml;
// - Porch's own backup files: they are meant to leave the phone only when
//   the person shares one. Bootstrap writes them to files/backups (the
//   app support folder on Android, see backupFolderFor).
// Both are excluded from cloud backup, device transfer and the older full
// backup. This is a file-content guard; Auto Backup itself cannot run
// under `flutter test`.
import 'dart:io';

import 'package:porch_app/backup_folder_adapter.dart';
import 'package:porch_app/data/backup_sink.dart';
import 'package:test/test.dart';

/// Every `<exclude …/>` in [xml] as "domain:path".
Set<String> excludes(String xml) => {
      for (final m in RegExp(r'<exclude\s+([^>]*?)/>').allMatches(xml))
        '${_attr(m.group(1)!, 'domain')}:${_attr(m.group(1)!, 'path')}',
    };

String? _attr(String attrs, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);

String section(String xml, String tag) {
  final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>').firstMatch(xml);
  expect(m, isNotNull, reason: 'no <$tag> section');
  return m!.group(1)!;
}

void main() {
  const res = 'android/app/src/main/res/xml';
  const secrets = 'sharedpref:FlutterSecureStorage.xml';
  const backups = 'file:$backupFolderName';
  const both = {secrets, backups};

  test('the manifest names both rules files and leaves allowBackup alone', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest, isNot(contains('android:allowBackup="false"')));
  });

  test('Android 12 and newer: cloud backup and device transfer skip the '
      'secrets and the backup folder, and nothing else', () {
    final rules = File('$res/data_extraction_rules.xml').readAsStringSync();
    expect(excludes(section(rules, 'cloud-backup')), both);
    expect(excludes(section(rules, 'device-transfer')), both);
  });

  test('Android 11 and older: full backup skips the same two, and nothing '
      'else', () {
    final rules = File('$res/backup_rules.xml').readAsStringSync();
    expect(excludes(section(rules, 'full-backup-content')), both);
  });

  test('backup files go in the excluded folder on Android', () {
    // path_provider's application support folder on Android is files/.
    const files = '/data/user/0/com.openhearth.porch_app/files';
    expect(backupFolderFor('android', applicationSupport: files).path,
        '$files/backups');
    expect(backupFolderName, 'backups');
  });
}
