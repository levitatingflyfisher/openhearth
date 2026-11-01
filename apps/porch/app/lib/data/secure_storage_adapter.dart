// secure_storage_adapter — the ONLY file in lib/data allowed to touch a
// Flutter plugin. Binds SecretStore (key_store.dart) to
// flutter_secure_storage: Android Keystore-backed EncryptedSharedPreferences
// / iOS and macOS Keychain, kept on this device.
//
// Deliberately zero logic: everything testable lives behind SecretStore and
// is tested against InMemorySecretStore. This adapter cannot run on the
// host VM (platform channels) — it is exercised only on-device, which
// HONEST-STATUS records. The purity test pins both properties: no other
// data file imports Flutter, and no other data file imports this adapter.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';

/// The options every Porch secret is stored with. On iOS and macOS the
/// keychain items are `first_unlock_this_device`: never in iCloud or
/// computer backups, never restored onto another device, and readable in
/// the background once the phone has been unlocked after a restart. The
/// Android side keeps the same promise through its backup rules.
const porchSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device),
);

class FlutterSecureStorageSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  FlutterSecureStorageSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? porchSecureStorage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
