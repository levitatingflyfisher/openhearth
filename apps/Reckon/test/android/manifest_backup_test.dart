import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/model_spec.dart';

/// Android's own backup to Google is the phone owner's choice (the owner's
/// ruling of 3 July 2026): the app leaves it on, and the owner switches it off
/// or on in Android settings. The encrypted .ohbk export stays the private
/// choice. What must never ride along, because it is useless or unsafe on
/// another phone: the recovery words and other keys (secure storage), and the
/// multi-gigabyte model files (Auto Backup gives up past 25 MB).
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final cloudRules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  final legacyRules = File('android/app/src/main/res/xml/backup_rules.xml');

  /// The `<exclude .../>` elements inside [section] ("cloud-backup",
  /// "device-transfer", or "full-backup-content"), as (domain, path) pairs.
  List<(String, String)> excludes(String xml, String section) {
    final block = RegExp('<$section[^>]*>(.*?)</$section>', dotAll: true)
        .firstMatch(xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ''));
    expect(block, isNotNull, reason: 'missing <$section> in the rules file');
    return [
      for (final m in RegExp(r'<exclude\s+domain="([^"]*)"\s+path="([^"]*)"')
          .allMatches(block!.group(1)!))
        (m.group(1)!, m.group(2)!),
    ];
  }

  void expectKeepsDataAndExcludesKeys(List<(String, String)> ex, String where) {
    expect(ex.any((e) => e.$2 == '.' || e.$2 == ''), isFalse,
        reason: '$where must not exclude a whole domain: it would drop '
            'reckon.sqlite, the decision journal');
    expect(
        ex.any((e) => e.$2 == 'app_flutter' || e.$2 == 'app_flutter/'),
        isFalse,
        reason: '$where must not exclude the documents directory, where '
            'reckon.sqlite lives');
    expect(ex.any((e) => e.$2.contains('reckon.sqlite')), isFalse,
        reason: '$where must not exclude the database');
    expect(
        ex.any((e) => e.$1 == 'sharedpref' && e.$2.startsWith('FlutterSecureStorage')),
        isTrue,
        reason: '$where must exclude secure storage, which holds the '
            'recovery words and keys');
    for (final spec in ReckonModelSpec.availableModels) {
      expect(ex.any((e) => e.$2.endsWith(spec.fileName)), isTrue,
          reason: '$where must exclude the model file ${spec.fileName}');
    }
  }

  test('manifest leaves Android backup on, as the phone owner chooses', () {
    final xml = manifest.readAsStringSync();
    expect(xml, contains('android:allowBackup="true"'));
    expect(xml, isNot(contains('android:allowBackup="false"')));
    expect(xml, isNot(contains('android:fullBackupContent="false"')));
  });

  test('manifest wires dataExtractionRules (Android 12+) and '
      'fullBackupContent (pre-12)', () {
    final xml = manifest.readAsStringSync();
    expect(xml,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(xml, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('data_extraction_rules keep the database and hold back keys and models',
      () {
    expect(cloudRules.existsSync(), isTrue);
    final xml = cloudRules.readAsStringSync();
    expectKeepsDataAndExcludesKeys(excludes(xml, 'cloud-backup'), 'cloud-backup');
    expectKeepsDataAndExcludesKeys(
        excludes(xml, 'device-transfer'), 'device-transfer');
  });

  test('backup_rules (pre-Android-12) keep the database and hold back keys '
      'and models', () {
    expect(legacyRules.existsSync(), isTrue);
    expectKeepsDataAndExcludesKeys(
        excludes(legacyRules.readAsStringSync(), 'full-backup-content'),
        'full-backup-content');
  });
}
