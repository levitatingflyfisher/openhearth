// The keychain must keep the identity on this device. Without a
// `_this_device` accessibility class, iOS and macOS keychain items ride in
// iCloud and encrypted computer backups and can be restored onto another
// device: the 12 words' entropy would travel, which the Android rules
// prevent on that side (android_backup_rules_test.dart). The adapter
// itself cannot run on the host; this pins the options it is built with.
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/secure_storage_adapter.dart';

void main() {
  test('iOS keychain items stay on this device, readable after first unlock',
      () {
    final ios = porchSecureStorage.iOptions.toMap();
    expect(ios['accessibility'], 'first_unlock_this_device');
    expect(ios['synchronizable'], 'false');
  });

  test('macOS keychain items stay on this device, readable after first '
      'unlock', () {
    final mac = porchSecureStorage.mOptions.toMap();
    expect(mac['accessibility'], 'first_unlock_this_device');
    expect(mac['synchronizable'], 'false');
  });

  test('Android keeps EncryptedSharedPreferences', () {
    expect(porchSecureStorage.aOptions.toMap()['encryptedSharedPreferences'],
        'true');
  });
}
