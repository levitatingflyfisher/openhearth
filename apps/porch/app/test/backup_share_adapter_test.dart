// The production share-sheet adapter, proven on the host against a fake
// SharePlatform: the backup reaches the platform as exactly one file with
// the backup's name and bytes.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:porch_app/backup_share_adapter.dart';

class _FakeSharePlatform extends SharePlatform {
  final calls = <ShareParams>[];
  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shares the blob as one named file through the platform sheet',
      () async {
    final fake = _FakeSharePlatform();
    SharePlatform.instance = fake;
    final blob = Uint8List.fromList([123, 34, 118, 34, 58, 49, 125]);

    await const SharePlusBackupShare()
        .share(blob, fileName: 'porch-20260926-120000.porchbackup');

    expect(fake.calls, hasLength(1));
    final p = fake.calls.single;
    expect(p.files, hasLength(1));
    expect(await p.files!.single.readAsBytes(), blob);
    expect(p.fileNameOverrides, ['porch-20260926-120000.porchbackup']);
  });
}
