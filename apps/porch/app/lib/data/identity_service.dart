// identity_service — first-launch keygen and every-launch rederivation
// (§3.1 steps 1–6). The 16 bytes in the key store ARE the identity; this
// service is the only writer.
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show Sodium;

import '../domain/domain.dart' show PorchIdentity;
import 'key_store.dart';

class IdentityService {
  final Sodium _sodium;
  final PorchKeyStore _keys;
  const IdentityService(this._sodium, this._keys);

  /// The stored identity, or null before onboarding.
  Future<PorchIdentity?> load() async {
    final entropy = await _keys.readEntropy();
    if (entropy == null) return null;
    return PorchIdentity.fromEntropy(_sodium, entropy);
  }

  /// First launch (or restore-from-seed when [entropy] is supplied):
  /// persist entropy, derive everything. Refuses to overwrite an existing
  /// identity — losing those 16 bytes means losing every group.
  Future<PorchIdentity> create({Uint8List? entropy}) async {
    if (await _keys.readEntropy() != null) {
      throw StateError(
          'an identity already exists; wipe() explicitly before re-creating');
    }
    final identity = entropy != null
        ? PorchIdentity.fromEntropy(_sodium, entropy)
        : PorchIdentity.generate(_sodium);
    await _keys.writeEntropy(identity.entropy);
    return identity;
  }
}
