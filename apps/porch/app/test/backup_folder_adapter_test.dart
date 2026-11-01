// Where backup files live, proven on the host. Every platform keeps them
// under Application Support: the system never clears it to free space, as
// it may clear the caches folder. On iOS and macOS that folder would go to
// iCloud and computer backups, so the backups folder is marked excluded
// from backup (NSURLIsExcludedFromBackupKey) through a method channel to a
// few lines of Swift. That Swift cannot run here; the Dart side is tested
// against a mock channel, and the Swift text is pinned below.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/backup_folder_adapter.dart';
import 'package:porch_app/data/backup_sink.dart' show backupFolderName;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const support = '/data/porch/Library/Application Support';

  test('every platform keeps backups under Application Support', () {
    for (final os in ['ios', 'macos', 'android', 'linux', 'windows']) {
      expect(backupFolderFor(os, applicationSupport: support).path,
          '$support/$backupFolderName',
          reason: os);
    }
  });

  test('iOS and macOS mark the folder excluded from backup; Android needs '
      'no call (its backup rules exclude the folder), nor do Linux and '
      'Windows', () {
    for (final os in ['ios', 'macos']) {
      expect(backupFolderFor(os, applicationSupport: support).exclude,
          isNotNull,
          reason: os);
    }
    for (final os in ['android', 'linux', 'windows']) {
      expect(
          backupFolderFor(os, applicationSupport: support).exclude, isNull,
          reason: os);
    }
  });

  test('the exclude call reaches the native side with the folder path',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, null));

    final folder = backupFolderFor('ios', applicationSupport: support);
    await folder.exclude!(folder.path);

    expect(backupExclusionChannel.name, 'porch/backup_exclusion');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'excludeFromBackup');
    expect(calls.single.arguments, {'path': '$support/$backupFolderName'});
  });

  test('a native refusal is an error, never a quiet success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, (call) async {
      throw PlatformException(code: 'exclude-failed');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, null));

    final folder = backupFolderFor('macos', applicationSupport: support);
    await expectLater(
        folder.exclude!(folder.path), throwsA(isA<PlatformException>()));
  });

  test('the Swift on iOS and macOS answers the channel by setting '
      'isExcludedFromBackup', () {
    for (final f in [
      'ios/Runner/AppDelegate.swift',
      'macos/Runner/MainFlutterWindow.swift',
    ]) {
      final swift = File(f).readAsStringSync();
      expect(swift, contains('"porch/backup_exclusion"'), reason: f);
      expect(swift, contains('"excludeFromBackup"'), reason: f);
      expect(swift, contains('isExcludedFromBackup = true'), reason: f);
    }
  });
}
