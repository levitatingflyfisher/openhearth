// Group-key lifecycle (BUILD-SPEC §3.2).
//
// The invariant lives here: channelId (the wire address), slotIds (per-member
// presence slots), bulletin writer ids and the dormant pushTopic are all
// derived FROM the group key — so rotating the key revokes decryption ability AND the routing
// address in one stroke, with zero server cooperation.
//
// Key policy (§3.2 step 3): encrypt with the newest epoch only; retain the
// last 2 epochs for decryption; prune retired epochs after 7 days.
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'support/bytes.dart';

const _chnCtx = 'PORCHCHN'; // crypto_kdf contexts: exactly 8 chars
const _sltCtx = 'PORCHSLT';
const _tpcCtx = 'PORCHTPC';
const _writerCtx = 'porch/bulletin-writer/v1'; // keyed BLAKE2b context

const int groupKeyBytes = 32;
const int epochGraceSeconds = 7 * 86400; // 7-day decrypt grace

/// channelId_e = base64url(crypto_kdf_derive_from_key(gk_e, 1, "PORCHCHN")).
/// Knowledge of it IS membership proof; it changes with every rotation.
String deriveChannelId(Sodium sodium, Uint8List gk) =>
    b64urlNoPad(_kdf(sodium, gk, _chnCtx, 32));

/// slotKey_e = crypto_kdf(gk_e, 1, "PORCHSLT");
/// slotId_m = base64url(BLAKE2b-128(member_sign_pk, key=slotKey_e)).
/// The server replaces per-member slots without knowing who a member is.
String deriveSlotId(Sodium sodium, Uint8List gk, Uint8List memberSignPk) {
  final slotKey = SecureKey.fromList(sodium, _kdf(sodium, gk, _sltCtx, 32));
  try {
    return b64urlNoPad(sodium.crypto.genericHash(
      message: memberSignPk,
      outLen: 16,
      key: slotKey,
    ));
  } finally {
    slotKey.dispose();
  }
}

/// writerId_m = base64url(BLAKE2b-128("porch/bulletin-writer/v1" ‖
/// member_sign_pk, key=gk_e)). A bulletin write names its writer by this,
/// so the relay can tell a second writer from the first. It shares nothing
/// with the member's presence slot id, so the relay cannot tie a member's
/// bulletins to their presence; it changes with every rotation.
String deriveBulletinWriterId(
    Sodium sodium, Uint8List gk, Uint8List memberSignPk) {
  if (gk.length != groupKeyBytes) {
    throw ArgumentError.value(gk.length, 'gk', 'group key must be 32 bytes');
  }
  final key = SecureKey.fromList(sodium, gk);
  try {
    return b64urlNoPad(sodium.crypto.genericHash(
      message: Uint8List.fromList([..._writerCtx.codeUnits, ...memberSignPk]),
      outLen: 16,
      key: key,
    ));
  } finally {
    key.dispose();
  }
}

/// pushTopic_e = crypto_kdf(gk_e, 1, "PORCHTPC")[0:12] — DORMANT in v1
/// (§1.3): derived and vector-tested now so v1.1 push needs no protocol
/// change. Nothing in v1 transmits it anywhere.
Uint8List derivePushTopic(Sodium sodium, Uint8List gk) =>
    Uint8List.sublistView(_kdf(sodium, gk, _tpcCtx, 16), 0, 12);

Uint8List _kdf(Sodium sodium, Uint8List gk, String ctx, int len) {
  if (gk.length != groupKeyBytes) {
    throw ArgumentError.value(gk.length, 'gk', 'group key must be 32 bytes');
  }
  final master = SecureKey.fromList(sodium, gk);
  try {
    final sub = sodium.crypto.kdf.deriveFromKey(
      masterKey: master,
      context: ctx,
      subkeyId: BigInt.one,
      subkeyLen: len,
    );
    try {
      return sub.extractBytes();
    } finally {
      sub.dispose();
    }
  } finally {
    master.dispose();
  }
}

/// One epoch of the group key.
class EpochKey {
  final int epoch;
  final Uint8List gk;

  /// Unix seconds when a newer epoch replaced this one; null while current.
  final int? retiredAt;

  const EpochKey({required this.epoch, required this.gk, this.retiredAt});
}

/// Immutable keyring for one group. `keys` is newest-first; only the first
/// entry ever encrypts.
class GroupKeyring {
  final List<EpochKey> keys;

  GroupKeyring._(this.keys);

  /// Group creation (§3.2 step 1): epoch 1, minted locally, server never sees.
  factory GroupKeyring.genesis(Uint8List gk) =>
      GroupKeyring.fromGrant(epoch: 1, gk: gk);

  /// Joining via grant: the keyring starts at whatever epoch was granted.
  factory GroupKeyring.fromGrant({required int epoch, required Uint8List gk}) {
    _checkKey(gk);
    return GroupKeyring._(
        List.unmodifiable([EpochKey(epoch: epoch, gk: gk)]));
  }

  /// The only epoch that encrypts.
  EpochKey get current => keys.first;

  /// Epochs allowed to decrypt (current + at most one grace epoch).
  List<EpochKey> get decryptable => keys;

  /// Adopt a rotation: the new epoch becomes current, the old current is
  /// retired at [nowSec], and anything older falls off (decrypt last 2).
  GroupKeyring adopt({
    required int epoch,
    required Uint8List gk,
    required int nowSec,
  }) {
    _checkKey(gk);
    if (epoch <= current.epoch) {
      throw ArgumentError.value(epoch, 'epoch',
          'must advance past current epoch ${current.epoch} (replay?)');
    }
    return GroupKeyring._(List.unmodifiable([
      EpochKey(epoch: epoch, gk: gk),
      EpochKey(epoch: current.epoch, gk: current.gk, retiredAt: nowSec),
    ]));
  }

  /// Drop retired epochs older than the 7-day grace. The current epoch is
  /// never pruned.
  GroupKeyring prune(int nowSec) => GroupKeyring._(List.unmodifiable([
        for (final k in keys)
          if (k.retiredAt == null || nowSec - k.retiredAt! <= epochGraceSeconds)
            k,
      ]));

  static void _checkKey(Uint8List gk) {
    if (gk.length != groupKeyBytes) {
      throw ArgumentError.value(
          gk.length, 'gk', 'group key must be 32 bytes');
    }
  }
}

/// Mint a fresh group key (group creation and every rotation).
Uint8List mintGroupKey(Sodium sodium) => sodium.randombytes.buf(groupKeyBytes);
