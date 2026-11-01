// Config regression-guard, not behavioral: asserts the Android manifest
// leaves Android's own backup on, as the owner ruled on 3 July 2026 ("leave
// google backup in as an option"). Whether it runs is the phone owner's
// choice in Android settings. There is no way to drive Android Auto Backup
// from `flutter test`, so this pins the config.
//
// What stays out of it: the recovery words. They live in the secure key
// store (flutter_secure_storage), whose preferences file is wrapped by a key
// that never leaves the phone. A copy of that file on another phone cannot be
// opened, and the words must not travel through Google backup, so the rules
// exclude that file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android backup is the phone owner’s choice', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('manifest leaves allowBackup on', () {
      expect(manifest, contains('android:allowBackup="true"'));
      expect(manifest, isNot(contains('android:allowBackup="false"')));
    });

    test('manifest does not switch off legacy full-backup content', () {
      expect(manifest, isNot(contains('android:fullBackupContent="false"')));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
    });

    test('manifest wires dataExtractionRules (Android 12+)', () {
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    for (final name in ['data_extraction_rules.xml', 'backup_rules.xml']) {
      test('$name keeps the database in and the recovery words out', () {
        final file = File('android/app/src/main/res/xml/$name');
        expect(file.existsSync(), isTrue,
            reason: 'the manifest must reference a rules file that exists');
        final rules = file.readAsStringSync();
        // The app's database and preferences are not excluded.
        expect(rules, isNot(contains('<exclude domain="database"')));
        expect(rules, isNot(contains('<exclude domain="root"')));
        expect(rules, isNot(contains('<exclude domain="file" />')));
        expect(
          rules,
          isNot(contains('<exclude domain="sharedpref" />')),
          reason: 'whole-domain exclusion of preferences is the old rule',
        );
        // The secure key store file (recovery words) is excluded.
        expect(
          rules,
          contains(
              '<exclude domain="sharedpref" path="FlutterSecureStorage.xml" />'),
        );
      });
    }
  });
}
