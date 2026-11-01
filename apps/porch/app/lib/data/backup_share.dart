// backup_share — hands the locked backup blob to somewhere the person
// chooses (the system share sheet on device). The backup sink writes into
// an app-private folder that no automatic backup takes and that uninstall
// deletes; sharing is how the file reaches a place that lasts
// (their files, another device, a USB stick).
//
// Platform-free port + test double; the share_plus adapter lives beside
// bootstrap (lib/backup_share_adapter.dart) so the data layer stays
// host-VM testable.
import 'dart:typed_data';

abstract interface class BackupShare {
  /// Offer [blob] to the platform as a file named [fileName].
  Future<void> share(Uint8List blob, {required String fileName});
}

/// Test double: records every share request.
class RecordingBackupShare implements BackupShare {
  final shared = <({String fileName, Uint8List blob})>[];
  @override
  Future<void> share(Uint8List blob, {required String fileName}) async {
    shared.add((fileName: fileName, blob: Uint8List.fromList(blob)));
  }
}
