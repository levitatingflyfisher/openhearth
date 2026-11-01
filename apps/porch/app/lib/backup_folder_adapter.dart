// backup_folder_adapter — where backup files live on a device, and the one
// native call that keeps them out of iCloud and computer backups.
//
// Every platform keeps backups under the app support folder: the system
// never clears it to free space, as it may clear the caches folder. Android
// excludes the `backups` folder in its backup rules. iOS and macOS have no
// such rules file, so the folder is marked with NSURLIsExcludedFromBackupKey
// through [backupExclusionChannel], answered by a few lines of Swift in
// ios/Runner/AppDelegate.swift and macos/Runner/MainFlutterWindow.swift.
// The Swift has not run here: only the Dart side is tested, on the host.
import 'package:flutter/services.dart';

import 'data/backup_sink.dart';

/// The channel to the Swift that sets the exclude-from-backup flag.
const backupExclusionChannel = MethodChannel('porch/backup_exclusion');

/// The backups folder under [applicationSupport], and the call that marks
/// it excluded from backup where the platform needs one (else null).
/// [operatingSystem] is named as `Platform.operatingSystem` names it.
({String path, ExcludeFromBackup? exclude}) backupFolderFor(
  String operatingSystem, {
  required String applicationSupport,
}) =>
    (
      path: '$applicationSupport/$backupFolderName',
      exclude: switch (operatingSystem) {
        'ios' || 'macos' => _excludeFromBackup,
        _ => null,
      },
    );

Future<void> _excludeFromBackup(String directory) =>
    backupExclusionChannel
        .invokeMethod<void>('excludeFromBackup', {'path': directory});
