// backup_share_adapter — the production [BackupShare]: the system share
// sheet via share_plus. The ONLY file that imports share_plus. The blob is
// passed as in-memory file data; share_plus writes the temporary file the
// platform needs, and on web offers it as a download.
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'data/backup_share.dart';

class SharePlusBackupShare implements BackupShare {
  const SharePlusBackupShare();

  @override
  Future<void> share(Uint8List blob, {required String fileName}) async {
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(blob,
            name: fileName, mimeType: 'application/octet-stream'),
      ],
      fileNameOverrides: [fileName],
      subject: 'Porch backup',
    ));
  }
}
