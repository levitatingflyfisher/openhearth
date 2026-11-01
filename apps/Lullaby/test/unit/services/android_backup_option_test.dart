// Android's own Google backup is the phone owner's choice (owner's ruling,
// 3 July 2026): the manifest allows it, and Android settings decide. What must
// never ride along is the key store, which holds the sync recovery words and
// this phone's household keys. Host config no widget test can see, so the
// manifest and rules are read as text.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res/xml';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the manifest allows Android backup and names rules for older phones', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:allowBackup="true"'));
    expect(manifest, isNot(contains('fullBackupContent="false"')));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  for (final name in ['data_extraction_rules', 'backup_rules']) {
    test('$name does not exclude the database or the files folder', () {
      final xml = _read('$_res/$name.xml');
      expect(xml, isNot(contains('<exclude domain="database"')));
      expect(xml, isNot(contains('<exclude domain="file"')));
    });

    test('$name keeps the key store (recovery words, sync keys) out of backup', () {
      final xml = _read('$_res/$name.xml');
      // flutter_secure_storage keeps its values and its wrapped key in this
      // one shared-preferences file.
      expect(xml, contains('path="FlutterSecureStorage.xml"'));
      expect(
          RegExp(r'<exclude\s+domain="sharedpref"\s+path="FlutterSecureStorage\.xml"')
              .hasMatch(xml),
          isTrue);
    });
  }

  test('data_extraction_rules covers both cloud backup and device transfer', () {
    final xml = _read('$_res/data_extraction_rules.xml');
    expect(xml, contains('<cloud-backup>'));
    expect(xml, contains('<device-transfer>'));
    expect('FlutterSecureStorage.xml'.allMatches(xml).length, 2);
  });
}
