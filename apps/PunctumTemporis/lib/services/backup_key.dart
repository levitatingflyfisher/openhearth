import 'dart:typed_data';

import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show CryptoService, DefaultCryptoService, KeyDerivation, OpenHearthMnemonic,
        SecureKeyStore;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart'
    show AppScopedSecureKeyStore;

import 'backup_stream_cipher.dart';

/// The household's 12 recovery words, turned into the key that seals a
/// PunctumTemporis backup.
///
/// All the crypto is the shared core's: BIP39 seed, then HKDF with PT's
/// own app domain (`openhearth.punctum.encryption.v1`), so the same
/// household words give PT a key no other fleet app shares. Each backup
/// file then gets its own key from that one and the file's random salt,
/// under the label [streamDomain].
abstract final class BackupKey {
  /// Namespaces the words in secure storage and isolates PT's key.
  static const appDomain = 'punctum';

  /// The HKDF label for the per-file key of an OHBS backup stream.
  static const streamDomain = 'openhearth.punctum.backupstream.v1';

  /// The keychain slot that holds this phone's words.
  static SecureKeyStore defaultStore() =>
      AppScopedSecureKeyStore(appId: appDomain);

  /// Whether [phrase] is 12 valid BIP39 words.
  static bool isValidPhrase(String phrase) =>
      OpenHearthMnemonic.validate(normalize(phrase));

  /// Lower case, single spaces: how the words are stored and derived.
  static String normalize(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  /// The per-file key deriver for [phrase].
  static Future<FileKeyDeriver> fromPhrase(
    String phrase, {
    CryptoService crypto = const DefaultCryptoService(),
  }) async {
    final keys =
        await crypto.deriveKeysFromPhrase(normalize(phrase), appDomain: appDomain);
    final master = Uint8List.fromList(keys.masterEncryptionKey);
    return (salt) => KeyDerivation.deriveKey(
          Uint8List.fromList([...master, ...salt]),
          domain: streamDomain,
        );
  }
}
