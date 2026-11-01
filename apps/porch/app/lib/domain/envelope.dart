// Envelope (BUILD-SPEC §3.3) — the ONE codec for every channel payload.
//
//   payload = canonical JSON {v:1, type, ...fields, issuedAt, epoch, senderSignPk}
//   sig     = crypto_sign_detached(payload, sign_sk)
//   wire    = nonce(24) ‖ XChaCha20-Poly1305(key=gk_epoch, nonce,
//               ad = "porch/v1" ‖ channelId ‖ epoch_le64,
//               msg = canonical JSON {payload, sig})
//
// Opening tries the newest epoch then the grace epoch, verifies the embedded
// signature, and cross-checks that the payload's claimed epoch matches the
// epoch whose key decrypted it (the AD already binds this; the explicit check
// is belt-and-braces). Every failure is a silent DROP (§3.3: a compromised
// server or a vandal can inject garbage but can never forge a friend).
// Roster-membership filtering happens one layer up, where a roster exists.
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'keyring.dart';
import 'support/bytes.dart';
import 'support/canonical_json.dart';

const _adPrefix = 'porch/v1';
const _nonceBytes = 24;

/// Payload keys owned by the envelope itself; `fields` may not use them.
const reservedEnvelopeKeys = {'v', 'type', 'issuedAt', 'epoch', 'senderSignPk'};

/// A decrypted, signature-verified envelope.
class OpenedEnvelope {
  /// Application fields (payload minus the reserved envelope keys).
  final Map<String, Object?> fields;
  final String type;
  final int issuedAt;
  final int epoch;
  final Uint8List senderSignPk;

  const OpenedEnvelope({
    required this.fields,
    required this.type,
    required this.issuedAt,
    required this.epoch,
    required this.senderSignPk,
  });
}

/// Seal one payload for the channel of [gk] at [epoch].
Uint8List sealEnvelope(
  Sodium sodium, {
  required String type,
  required Map<String, Object?> fields,
  required int issuedAt,
  required int epoch,
  required Uint8List gk,
  required KeyPair senderSign,
}) {
  for (final k in fields.keys) {
    if (reservedEnvelopeKeys.contains(k)) {
      throw ArgumentError.value(k, 'fields', 'reserved envelope key');
    }
  }
  final payload = <String, Object?>{
    'v': 1,
    'type': type,
    ...fields,
    'issuedAt': issuedAt,
    'epoch': epoch,
    'senderSignPk': b64(senderSign.publicKey),
  };
  final sig = sodium.crypto.sign.detached(
    message: canonicalJsonBytes(payload),
    secretKey: senderSign.secretKey,
  );
  return _encrypt(
    sodium,
    plaintext: canonicalJsonBytes({'payload': payload, 'sig': b64(sig)}),
    epoch: epoch,
    gk: gk,
  );
}

/// Open a wire blob against [keyring]. Returns null on ANY failure — silence
/// is the contract; unverifiable bytes carry no information worth logging.
OpenedEnvelope? openEnvelope(
  Sodium sodium, {
  required Uint8List wire,
  required GroupKeyring keyring,
}) {
  if (wire.length <= _nonceBytes) return null;
  final nonce = Uint8List.sublistView(wire, 0, _nonceBytes);
  final ct = Uint8List.sublistView(wire, _nonceBytes);
  for (final ek in keyring.decryptable) {
    final key = SecureKey.fromList(sodium, ek.gk);
    Uint8List plain;
    try {
      plain = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ct,
        nonce: nonce,
        key: key,
        additionalData: _ad(sodium, ek),
      );
    } on Object {
      continue; // not this epoch — try the grace key
    } finally {
      key.dispose();
    }
    return _verify(sodium, plain, ek.epoch); // decrypted: verdict is final
  }
  return null;
}

OpenedEnvelope? _verify(Sodium sodium, Uint8List plain, int decryptedEpoch) {
  try {
    final outer = jsonDecode(utf8.decode(plain));
    if (outer is! Map<String, Object?>) return null;
    final payload = outer['payload'];
    final sigB64 = outer['sig'];
    if (payload is! Map<String, Object?> || sigB64 is! String) return null;

    final type = payload['type'];
    final issuedAt = payload['issuedAt'];
    final epoch = payload['epoch'];
    final senderB64 = payload['senderSignPk'];
    if (payload['v'] != 1 ||
        type is! String ||
        issuedAt is! int ||
        epoch is! int ||
        senderB64 is! String) {
      return null;
    }
    if (epoch != decryptedEpoch) return null; // payload lies about its epoch

    final senderPk = b64decode(senderB64);
    final ok = sodium.crypto.sign.verifyDetached(
      message: canonicalJsonBytes(payload),
      signature: b64decode(sigB64),
      publicKey: senderPk,
    );
    if (!ok) return null;

    return OpenedEnvelope(
      fields: {
        for (final e in payload.entries)
          if (!reservedEnvelopeKeys.contains(e.key)) e.key: e.value,
      },
      type: type,
      issuedAt: issuedAt,
      epoch: epoch,
      senderSignPk: senderPk,
    );
  } on Object {
    return null; // malformed JSON / base64 / key length — drop
  }
}

Uint8List _ad(Sodium sodium, EpochKey ek) => concatBytes([
      utf8.encode(_adPrefix),
      utf8.encode(deriveChannelId(sodium, ek.gk)),
      le64(ek.epoch),
    ]);

Uint8List _encrypt(
  Sodium sodium, {
  required Uint8List plaintext,
  required int epoch,
  required Uint8List gk,
}) {
  final nonce = sodium.randombytes.buf(_nonceBytes);
  final key = SecureKey.fromList(sodium, gk);
  try {
    final ct = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
      message: plaintext,
      nonce: nonce,
      key: key,
      additionalData: _ad(sodium, EpochKey(epoch: epoch, gk: gk)),
    );
    return concatBytes([nonce, ct]);
  } finally {
    key.dispose();
  }
}

// ---------------------------------------------------------------------------
// Test seams: adversarial tests must craft envelopes a well-behaved client
// cannot (forged sig, lying epoch, garbage plaintext). Visible for testing
// only — production code has no business here.
// ---------------------------------------------------------------------------

@visibleForTesting
Uint8List rawSealForTest(
  Sodium sodium, {
  required Map<String, Object?> payload,
  required Uint8List sig,
  required int epoch,
  required Uint8List gk,
}) =>
    _encrypt(
      sodium,
      plaintext: canonicalJsonBytes({'payload': payload, 'sig': b64(sig)}),
      epoch: epoch,
      gk: gk,
    );

@visibleForTesting
Uint8List rawAeadForTest(
  Sodium sodium, {
  required Uint8List plaintext,
  required int epoch,
  required Uint8List gk,
}) =>
    _encrypt(sodium, plaintext: plaintext, epoch: epoch, gk: gk);
