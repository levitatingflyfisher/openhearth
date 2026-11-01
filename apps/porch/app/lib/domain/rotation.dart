// Key rotation on membership change (BUILD-SPEC §3.6).
//
// Departures (REMOVE / LEAVE) — and ONLY departures — trigger rotation
// (§3.5 step 6: joins do not rotate). The deterministic rotator mints
// gk_{e+1}, seals a bundle to each remaining member's box key (anonymous
// mailbox fan-out), and duplicates the bundles on the OLD channel bulletin
// as a latency optimization the departed member can open but not use.
//
// Adoption is made total by the server-assigned bulletin seq; the
// deterministic tiebreak (admin-authored, then smallest BLAKE2b(gk)) is only
// a fallback for mailbox-only races. Any delivery order converges — that is
// property-tested, not hoped.
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'envelope.dart';
import 'identity.dart';
import 'keyring.dart';
import 'roster.dart';
import 'support/bytes.dart';
import 'support/canonical_json.dart';

/// The departed member's pk if [op] is a departure (rotation trigger);
/// null for JOIN / PROFILE / TRANSFER_ADMIN (which never rotate).
Uint8List? departureOf(RosterOp op) => switch (op) {
      RemoveOp(:final memberPk) => memberPk,
      LeaveOp(:final senderSignPk) => senderSignPk,
      _ => null,
    };

/// Who rotates (§3.6 step 2): the current admin — unless the admin is the
/// one departing, in which case the deterministic successor (who also
/// becomes admin). One rule, implemented once, in roster.dart.
Uint8List? electRotator(Roster preDepartureRoster,
    {required Uint8List departedPk}) {
  final admin = preDepartureRoster.adminPk;
  if (admin != null && !bytesEqual(admin, departedPk)) return admin;
  return successorOf(preDepartureRoster, departedPk);
}

/// A decrypted, signature-verified rotation grant.
class RotationBundle {
  final String groupUuid;
  final int epoch;
  final Uint8List gk;

  /// The post-departure roster as the rotator signed it.
  final Roster roster;
  final int issuedAt;
  final Uint8List rotatorSignPk;

  const RotationBundle({
    required this.groupUuid,
    required this.epoch,
    required this.gk,
    required this.roster,
    required this.issuedAt,
    required this.rotatorSignPk,
  });
}

/// What the rotator sends: per-member sealed mailbox blobs + the bulletin
/// duplicate riding the old channel.
class RotationFanout {
  /// mailboxId → sealed bundle. The app layer posts these anonymously with
  /// 0–30 s jitter (jitter scheduling is W5 scope).
  final Map<String, Uint8List> mailboxBlobs;

  /// Envelope (type ROTATION) under the OLD epoch for the old channel
  /// bulletin: outer opens for anyone with gk_e — including the departed
  /// member — but the inner per-member boxes do not.
  final Uint8List bulletinDupEnvelope;

  const RotationFanout(
      {required this.mailboxBlobs, required this.bulletinDupEnvelope});
}

/// Build the full fan-out for one rotation (§3.6 step 3).
RotationFanout buildRotation(
  Sodium sodium, {
  required String groupUuid,
  required int newEpoch,
  required Uint8List newGk,
  required Roster postRoster,
  required KeyPair rotatorSign,
  required int issuedAt,
  required int oldEpoch,
  required Uint8List oldGk,
}) {
  final signed = _signedBundleBytes(
    sodium,
    groupUuid: groupUuid,
    epoch: newEpoch,
    gk: newGk,
    roster: postRoster,
    issuedAt: issuedAt,
    rotatorSign: rotatorSign,
  );

  final mailboxBlobs = <String, Uint8List>{};
  final dupBoxes = <String, Object?>{};
  for (final m in postRoster.members) {
    if (bytesEqual(m.signPk, rotatorSign.publicKey)) continue; // self
    final sealed =
        sodium.crypto.box.seal(message: signed, publicKey: m.boxPk);
    mailboxBlobs[deriveMailboxId(sodium, m.signPk)] = sealed;
    dupBoxes[b64(m.signPk)] = b64(sealed);
  }

  return RotationFanout(
    mailboxBlobs: mailboxBlobs,
    bulletinDupEnvelope: sealEnvelope(
      sodium,
      type: 'ROTATION',
      fields: {'boxes': dupBoxes},
      issuedAt: issuedAt,
      epoch: oldEpoch,
      gk: oldGk,
      senderSign: rotatorSign,
    ),
  );
}

/// Open a sealed rotation bundle addressed to [myBox]. Null on any failure
/// (not mine, tampered, bad signature).
RotationBundle? openRotationBundle(
  Sodium sodium, {
  required KeyPair myBox,
  required Uint8List sealed,
}) {
  try {
    final plain = sodium.crypto.box.sealOpen(
      cipherText: sealed,
      publicKey: myBox.publicKey,
      secretKey: myBox.secretKey,
    );
    return _parseSignedBundle(sodium, plain);
  } on Object {
    return null;
  }
}

/// Recover my bundle from the bulletin duplicate (type ROTATION).
RotationBundle? rotationFromDupEnvelope(
  Sodium sodium, {
  required OpenedEnvelope env,
  required KeyPair myBox,
  required Uint8List mySignPk,
}) {
  if (env.type != 'ROTATION') return null;
  try {
    final boxes = env.fields['boxes'];
    if (boxes is! Map) return null;
    final mine = boxes[b64(mySignPk)];
    if (mine is! String) return null;
    return openRotationBundle(sodium,
        myBox: myBox, sealed: b64decode(mine));
  } on Object {
    return null;
  }
}

/// Validate an opened bundle against local knowledge (§3.6 step 4).
///
/// - Fresh rotation (epoch advances, unsolicited): the rotator must be the
///   deterministically expected one — the admin, or the successor when the
///   admin is the departed ([departedPk]).
/// - [selfHeal] (I posted a REKEY_REQUEST, or I'm restoring from backup):
///   re-grants of the group's EXISTING epoch may come from ANY member of the
///   roster I still know. Without the flag that relaxation does not apply.
bool validateRotation(
  RotationBundle bundle, {
  required Roster localRoster,
  required int currentEpoch,
  Uint8List? departedPk,
  bool selfHeal = false,
}) {
  if (bundle.epoch <= currentEpoch) return false; // stale or replay
  if (selfHeal) {
    return localRoster.isMember(bundle.rotatorSignPk);
  }
  if (bundle.epoch != currentEpoch + 1) return false; // gap → go self-heal
  final expected = departedPk != null
      ? electRotator(localRoster, departedPk: departedPk)
      : localRoster.adminPk;
  return expected != null && bytesEqual(expected, bundle.rotatorSignPk);
}

// ---------------------------------------------------------------------------
// Adoption (§3.6 step 4): among VALID competing bundles for the same new
// epoch, lowest bulletin seq wins; mailbox-only bundles fall back to
// admin-authored, then smallest BLAKE2b-256(gk).
// ---------------------------------------------------------------------------

class RotationCandidate {
  final RotationBundle bundle;

  /// Server-assigned bulletin seq, if this bundle was seen on the bulletin;
  /// null for mailbox-only delivery.
  final int? seq;
  const RotationCandidate({required this.bundle, this.seq});
}

/// Deterministic winner among competing candidates — every member computes
/// the same answer regardless of delivery order. Null for an empty list.
RotationCandidate? electRotationWinner(
    Sodium sodium, List<RotationCandidate> candidates) {
  if (candidates.isEmpty) return null;
  final ranked = List.of(candidates);
  int cmp(RotationCandidate a, RotationCandidate b) {
    // Seq-bearing bundles outrank mailbox-only ones; lowest seq wins.
    if (a.seq != null || b.seq != null) {
      if (a.seq == null) return 1;
      if (b.seq == null) return -1;
      return a.seq!.compareTo(b.seq!);
    }
    // Mailbox-only: admin-authored (per the bundle's own post-departure
    // roster) wins...
    final aAdmin = a.bundle.roster.isAdminPk(a.bundle.rotatorSignPk);
    final bAdmin = b.bundle.roster.isAdminPk(b.bundle.rotatorSignPk);
    if (aAdmin != bAdmin) return aAdmin ? -1 : 1;
    // ...else smallest hash of the proposed key.
    final ha = sodium.crypto.genericHash(message: a.bundle.gk, outLen: 32);
    final hb = sodium.crypto.genericHash(message: b.bundle.gk, outLen: 32);
    for (var i = 0; i < 32; i++) {
      if (ha[i] != hb[i]) return ha[i] - hb[i];
    }
    return 0;
  }

  ranked.sort(cmp);
  return ranked.first;
}

// ---------------------------------------------------------------------------
// Rekey-request self-heal (§3.6 step 6): a member who missed rotation blobs
// posts a signed request on the old channel; any current member re-grants
// the current epoch to the roster-verified box key.
// ---------------------------------------------------------------------------

class RekeyRequest {
  final Uint8List requesterSignPk;
  final Uint8List requesterBoxPk;
  const RekeyRequest(
      {required this.requesterSignPk, required this.requesterBoxPk});
}

Uint8List buildRekeyRequestEnvelope(
  Sodium sodium, {
  required Uint8List myBoxPk,
  required int issuedAt,
  required int epoch,
  required Uint8List gk,
  required KeyPair senderSign,
}) =>
    sealEnvelope(
      sodium,
      type: 'REKEY_REQUEST',
      fields: {'boxPk': b64(myBoxPk)},
      issuedAt: issuedAt,
      epoch: epoch,
      gk: gk,
      senderSign: senderSign,
    );

/// Validate a REKEY_REQUEST: the (signature-verified) sender must be a
/// roster member AND the claimed box key must be the roster's box key for
/// that member — the current epoch is never sealed to an unvouched address.
RekeyRequest? rekeyRequestFromEnvelope(OpenedEnvelope env,
    {required Roster roster}) {
  if (env.type != 'REKEY_REQUEST') return null;
  try {
    final member = roster.memberOf(env.senderSignPk);
    if (member == null) return null;
    final boxPk = b64decode(env.fields['boxPk'] as String);
    if (!bytesEqual(boxPk, member.boxPk)) return null;
    return RekeyRequest(
        requesterSignPk: env.senderSignPk, requesterBoxPk: boxPk);
  } on Object {
    return null;
  }
}

/// Any current member answers a valid request with the CURRENT epoch,
/// sealed to the verified box key. Same bundle format as a rotation —
/// the requester validates it with `selfHeal: true`.
Uint8List buildRegrant(
  Sodium sodium, {
  required RekeyRequest request,
  required String groupUuid,
  required int currentEpoch,
  required Uint8List currentGk,
  required Roster roster,
  required KeyPair responderSign,
  required int issuedAt,
}) =>
    sodium.crypto.box.seal(
      message: _signedBundleBytes(
        sodium,
        groupUuid: groupUuid,
        epoch: currentEpoch,
        gk: currentGk,
        roster: roster,
        issuedAt: issuedAt,
        rotatorSign: responderSign,
      ),
      publicKey: request.requesterBoxPk,
    );

// ---------------------------------------------------------------------------
// Shared signed-bundle codec: canonical {core, rotatorSignPk, sig}.
// ---------------------------------------------------------------------------

Uint8List _signedBundleBytes(
  Sodium sodium, {
  required String groupUuid,
  required int epoch,
  required Uint8List gk,
  required Roster roster,
  required int issuedAt,
  required KeyPair rotatorSign,
}) {
  if (gk.length != groupKeyBytes) {
    throw ArgumentError.value(gk.length, 'gk', 'group key must be 32 bytes');
  }
  final core = <String, Object?>{
    'v': 1,
    'type': 'rotation',
    'groupUuid': groupUuid,
    'epoch': epoch,
    'gk': b64(gk),
    'roster': roster.toJson(),
    'issuedAt': issuedAt,
  };
  final sig = sodium.crypto.sign.detached(
    message: canonicalJsonBytes(core),
    secretKey: rotatorSign.secretKey,
  );
  return canonicalJsonBytes({
    'core': core,
    'rotatorSignPk': b64(rotatorSign.publicKey),
    'sig': b64(sig),
  });
}

RotationBundle? _parseSignedBundle(Sodium sodium, Uint8List plain) {
  try {
    final outer = decodeJsonMap(plain);
    if (outer == null) return null;
    final core = outer['core'];
    final rotatorB64 = outer['rotatorSignPk'];
    final sigB64 = outer['sig'];
    if (core is! Map<String, Object?> ||
        rotatorB64 is! String ||
        sigB64 is! String) {
      return null;
    }
    if (core['v'] != 1 || core['type'] != 'rotation') return null;
    final rotatorPk = b64decode(rotatorB64);
    if (!sodium.crypto.sign.verifyDetached(
      message: canonicalJsonBytes(core),
      signature: b64decode(sigB64),
      publicKey: rotatorPk,
    )) {
      return null;
    }
    final gk = b64decode(core['gk'] as String);
    if (gk.length != groupKeyBytes) return null;
    return RotationBundle(
      groupUuid: core['groupUuid'] as String,
      epoch: core['epoch'] as int,
      gk: gk,
      roster: Roster.fromJson(core['roster'] as List<Object?>),
      issuedAt: core['issuedAt'] as int,
      rotatorSignPk: rotatorPk,
    );
  } on Object {
    return null;
  }
}

/// Adversarial test seam: a bundle whose claimed rotator differs from the
/// actual signer — openRotationBundle must refuse it.
@visibleForTesting
Uint8List forgeRotationBundleForTest(
  Sodium sodium, {
  required String groupUuid,
  required int epoch,
  required Uint8List gk,
  required Roster roster,
  required int issuedAt,
  required Uint8List claimedRotatorPk,
  required KeyPair actualSigner,
  required Uint8List recipientBoxPk,
}) {
  final core = <String, Object?>{
    'v': 1,
    'type': 'rotation',
    'groupUuid': groupUuid,
    'epoch': epoch,
    'gk': b64(gk),
    'roster': roster.toJson(),
    'issuedAt': issuedAt,
  };
  final sig = sodium.crypto.sign.detached(
    message: canonicalJsonBytes(core),
    secretKey: actualSigner.secretKey,
  );
  return sodium.crypto.box.seal(
    message: canonicalJsonBytes({
      'core': core,
      'rotatorSignPk': b64(claimedRotatorPk), // the lie
      'sig': b64(sig),
    }),
    publicKey: recipientBoxPk,
  );
}
