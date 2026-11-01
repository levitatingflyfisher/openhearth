import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../core/errors/result.dart';
import '../../services/backup/webdav_backup_service.dart';

/// The WebDAV transport. A provider so tests can point it at a server in
/// memory.
final webDavServiceProvider = Provider<WebDavBackupService>((ref) {
  return WebDavBackupService();
});

/// What the WebDAV screen tells the household about what leaves the phone.
const webDavWhatLeavesText =
    'Still Life locks your inventory with your recovery words before it '
    'leaves this phone, the same way as the encrypted backup. Your server '
    'stores a file it cannot read. It can still see the file size, when it '
    'changed, and your login. Photos are not included.';

/// Shown when the server holds a plain JSON export from an older build.
const webDavOldPlainFileMessage =
    'The file on your server is an old unencrypted backup, so Still Life '
    'will not restore it from here. Tap Back Up Now to replace it with an '
    'encrypted one. To bring the old file in, download it and use Import '
    'Data in Settings.';

/// Shown when Back Up Now is tapped on a device with no recovery words.
const webDavNeedsWordsMessage =
    'Set up encrypted backup in Settings first. The WebDAV backup is locked '
    'with the same recovery words.';

/// Thrown by [WebDavBackupFlow.upload] when the device has no recovery
/// words, so there is no key to lock the backup with.
class WebDavNeedsWordsException implements Exception {
  const WebDavNeedsWordsException();

  @override
  String toString() => webDavNeedsWordsMessage;
}

/// The WebDAV backup, made and opened by the encrypted backup itself.
///
/// The upload is the `.ohbk` records backup: [BackupRepository.export]
/// under the recovery-words key, AEAD context `stilllife-backup/v1`. The
/// restore hands the downloaded bytes to [BackupFlow.restorePickedBlob],
/// the same path as Restore from backup: decrypt first, ask for the words
/// when this device's key does not open it, preview, a safety snapshot,
/// then the merge and the restore hook. There is no second copy of the
/// crypto here, and no path that reads plain JSON from the server.
class WebDavBackupFlow {
  const WebDavBackupFlow();

  /// Seals today's records, proves the sealed bytes open, and sends them.
  ///
  /// Throws [WebDavNeedsWordsException] when the device has no recovery
  /// words; nothing is sent. Records "Last backup" only after the server
  /// took the file.
  Future<Result<void>> upload(
    T Function<T>(ProviderListenable<T> provider) read,
  ) async {
    final key = (await read(authNotifierProvider.future)).masterEncryptionKey;
    if (key == null) throw const WebDavNeedsWordsException();

    final repo = read(backupRepositoryProvider);
    final sealed = await repo.export(key);
    // A backup that does not open is not a backup: check before sending,
    // as the encrypted backup's own export does.
    await repo.open(sealed, key);

    final result = await read(webDavServiceProvider).backup(sealed);
    if (result.isSuccess) {
      try {
        await read(authNotifierProvider.notifier).recordBackupCompleted();
      } on Object {
        // The file is on the server. A failed stamp is not a failed backup.
      }
    }
    return result;
  }

  /// Downloads the stored backup's bytes. Opening them is [restore]'s job.
  Future<Result<Uint8List>> download(
    T Function<T>(ProviderListenable<T> provider) read,
  ) => read(webDavServiceProvider).restore();

  /// Restores downloaded [bytes] through the encrypted backup's restore.
  /// An old plain JSON file is refused by name and nothing is written.
  /// Shows its own messages.
  Future<void> restore(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
  ) async {
    if (isOldPlainBackup(bytes)) {
      _say(context, webDavOldPlainFileMessage);
      return;
    }
    await const BackupFlow().restorePickedBlob(context, ref, bytes);
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Whether [bytes] are the plain JSON export older builds sent to WebDAV.
/// Anything else that is not sealed goes on to the restore, which calls it
/// damaged.
bool isOldPlainBackup(Uint8List bytes) {
  if (WebDavBackupService.isSealed(bytes)) return false;
  try {
    final decoded = json.decode(utf8.decode(bytes));
    return decoded is Map<String, dynamic> && decoded['app'] == 'still_life';
  } on FormatException {
    return false;
  }
}
