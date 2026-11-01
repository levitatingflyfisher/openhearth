// Invite handshake (BUILD-SPEC §3.5) — trust rooted in the link.
//
// From one 32-byte token t (which rides the porch:// fragment or a pasted
// code and NEVER touches the server), keyed BLAKE2b derives:
//   inviteId   — the only thing registered server-side (22 chars)
//   k_i        — secretbox key for Bob's intro blob
//   fetchProof — gate for fetching the join blob / posting the grant
//   grantProof — gate for Bob's grant pickup (deleted after retrieval)
//
// The server can verify none of these against anything; it stores ciphertext
// addressed by unguessable strings. Whoever holds t within the TTL joins as
// "Bob" — the PRD names invite-link secrecy as the trust root, and the
// roster shows the join.
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'envelope.dart';
import 'keyring.dart';
import 'roster.dart';
import 'support/bytes.dart';
import 'support/canonical_json.dart';

const _idCtx = 'porch/inv/id/v1';
const _keyCtx = 'porch/inv/key/v1';
const _fetchCtx = 'porch/inv/fetch/v1';
const _grantCtx = 'porch/inv/grant/v1';
const _linkPrefix = 'porch://i#';

/// The invite token and its derivations. All four values are
/// gh(out=32, key=t, msg=context) — keyed BLAKE2b domain separation.
class InviteToken {
  final Uint8List t;

  InviteToken(this.t) {
    if (t.length != 32) {
      throw ArgumentError.value(t.length, 't', 'invite token must be 32 bytes');
    }
  }

  factory InviteToken.mint(Sodium sodium) =>
      InviteToken(sodium.randombytes.buf(32));

  /// base64url(gh("porch/inv/id/v1"))[0:22] — the server-visible name.
  String inviteId(Sodium sodium) =>
      b64urlNoPad(_gh(sodium, _idCtx)).substring(0, 22);

  /// k_i — the secretbox key protecting Bob's intro.
  Uint8List inviteKey(Sodium sodium) => _gh(sodium, _keyCtx);

  /// Gate for GET join / POST grant (computable only with t).
  String fetchProof(Sodium sodium) => b64urlNoPad(_gh(sodium, _fetchCtx));

  /// Gate for Bob's grant pickup.
  String grantProof(Sodium sodium) => b64urlNoPad(_gh(sodium, _grantCtx));

  /// The shareable link: `porch://i#<inviteId>.<base64url(t)>`.
  /// The token rides the fragment — it never appears in any HTTP request.
  String toLink(Sodium sodium) => '$_linkPrefix${toCode(sodium)}';

  /// The paste-the-code form (primary tested path): `<inviteId>.<b64url(t)>`.
  String toCode(Sodium sodium) => '${inviteId(sodium)}.${b64urlNoPad(t)}';

  /// Parse a porch:// link or bare pasted code. Returns null unless the
  /// embedded inviteId matches the token's own derivation — a mismatched or
  /// truncated paste must fail loudly at the door, not at the relay.
  static InviteToken? parse(Sodium sodium, String input) {
    var s = input.trim();
    if (s.startsWith(_linkPrefix)) s = s.substring(_linkPrefix.length);
    final dot = s.lastIndexOf('.');
    if (dot <= 0 || dot == s.length - 1) return null;
    final id = s.substring(0, dot);
    final Uint8List t;
    try {
      t = b64urlNoPadDecode(s.substring(dot + 1));
    } on Object {
      return null;
    }
    if (t.length != 32) return null;
    final token = InviteToken(t);
    if (token.inviteId(sodium) != id) return null;
    return token;
  }

  Uint8List _gh(Sodium sodium, String context) {
    final key = SecureKey.fromList(sodium, t);
    try {
      return sodium.crypto.genericHash(
        message: Uint8List.fromList(context.codeUnits),
        outLen: 32,
        key: key,
      );
    } finally {
      key.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Join blob (§3.5 step 3): Bob's sealed self-introduction.
// Layout: nonce(24) ‖ secretbox(k_i, canonical {v, boxPk, signPk,
// displayName, contactNote}). The server stores it, cannot read it.
// ---------------------------------------------------------------------------

class JoinIntro {
  final Uint8List signPk;
  final Uint8List boxPk;
  final String displayName;
  final String contactNote;
  const JoinIntro({
    required this.signPk,
    required this.boxPk,
    required this.displayName,
    required this.contactNote,
  });
}

Uint8List buildJoinBlob(
  Sodium sodium, {
  required InviteToken token,
  required Uint8List signPk,
  required Uint8List boxPk,
  required String displayName,
  required String contactNote,
}) {
  final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
  final key = SecureKey.fromList(sodium, token.inviteKey(sodium));
  try {
    final ct = sodium.crypto.secretBox.easy(
      message: canonicalJsonBytes({
        'v': 1,
        'signPk': b64(signPk),
        'boxPk': b64(boxPk),
        'displayName': displayName,
        'contactNote': contactNote,
      }),
      nonce: nonce,
      key: key,
    );
    return concatBytes([nonce, ct]);
  } finally {
    key.dispose();
  }
}

JoinIntro? openJoinBlob(
  Sodium sodium, {
  required InviteToken token,
  required Uint8List blob,
}) {
  final nonceBytes = sodium.crypto.secretBox.nonceBytes;
  if (blob.length <= nonceBytes) return null;
  final key = SecureKey.fromList(sodium, token.inviteKey(sodium));
  try {
    final plain = sodium.crypto.secretBox.openEasy(
      cipherText: Uint8List.sublistView(blob, nonceBytes),
      nonce: Uint8List.sublistView(blob, 0, nonceBytes),
      key: key,
    );
    final m = decodeJsonMap(plain);
    if (m == null || m['v'] != 1) return null;
    final signPk = b64decode(m['signPk'] as String);
    final boxPk = b64decode(m['boxPk'] as String);
    if (signPk.length != 32 || boxPk.length != 32) return null;
    return JoinIntro(
      signPk: signPk,
      boxPk: boxPk,
      displayName: m['displayName'] as String,
      contactNote: m['contactNote'] as String,
    );
  } on Object {
    return null;
  } finally {
    key.dispose();
  }
}

// ---------------------------------------------------------------------------
// Grant blob (§3.5 step 4): the group key + signed roster, sealed to Bob.
// The granter signs the WHOLE core (roster + gk + names) — Bob's TOFU root
// is the out-of-band link; the signature proves the grant is internally
// consistent and authored by a roster member.
// ---------------------------------------------------------------------------

class Grant {
  final String groupUuid;
  final String groupName;
  final int epoch;
  final Uint8List gk;
  final Roster roster;
  final Uint8List granterSignPk;
  const Grant({
    required this.groupUuid,
    required this.groupName,
    required this.epoch,
    required this.gk,
    required this.roster,
    required this.granterSignPk,
  });
}

Uint8List buildGrantBlob(
  Sodium sodium, {
  required Uint8List recipientBoxPk,
  required String groupUuid,
  required String groupName,
  required int epoch,
  required Uint8List gk,
  required Roster roster,
  required int grantedAt,
  required KeyPair granterSign,
}) {
  final core = <String, Object?>{
    'v': 1,
    'groupUuid': groupUuid,
    'groupName': groupName,
    'epoch': epoch,
    'gk': b64(gk),
    'roster': roster.toJson(),
    'grantedAt': grantedAt,
  };
  final sig = sodium.crypto.sign.detached(
    message: canonicalJsonBytes(core),
    secretKey: granterSign.secretKey,
  );
  return sodium.crypto.box.seal(
    message: canonicalJsonBytes({
      'core': core,
      'granterSignPk': b64(granterSign.publicKey),
      'sig': b64(sig),
    }),
    publicKey: recipientBoxPk,
  );
}

/// Open + verify a grant. Null on ANY failure: not sealed to me, tampered,
/// bad signature, granter absent from the roster it delivered.
Grant? openGrantBlob(
  Sodium sodium, {
  required KeyPair myBox,
  required Uint8List blob,
}) {
  try {
    final plain = sodium.crypto.box.sealOpen(
      cipherText: blob,
      publicKey: myBox.publicKey,
      secretKey: myBox.secretKey,
    );
    final outer = decodeJsonMap(plain);
    if (outer == null) return null;
    final core = outer['core'];
    final granterB64 = outer['granterSignPk'];
    final sigB64 = outer['sig'];
    if (core is! Map<String, Object?> ||
        granterB64 is! String ||
        sigB64 is! String) {
      return null;
    }
    if (core['v'] != 1) return null;
    final granterPk = b64decode(granterB64);
    if (!sodium.crypto.sign.verifyDetached(
      message: canonicalJsonBytes(core),
      signature: b64decode(sigB64),
      publicKey: granterPk,
    )) {
      return null;
    }
    final roster = Roster.fromJson(core['roster'] as List<Object?>);
    if (!roster.isMember(granterPk)) return null; // forged provenance
    final gk = b64decode(core['gk'] as String);
    if (gk.length != groupKeyBytes) return null;
    return Grant(
      groupUuid: core['groupUuid'] as String,
      groupName: core['groupName'] as String,
      epoch: core['epoch'] as int,
      gk: gk,
      roster: roster,
      granterSignPk: granterPk,
    );
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Escrow (§3.5 step 2, PRD gate 4): the invite token, group-encrypted and
// pinned to the bulletin, so ANY current admin can fulfill an orphaned
// invite after the inviter leaves.
// ---------------------------------------------------------------------------

class EscrowRecord {
  final InviteToken token;
  final String inviteId;
  final int expiresAt;
  const EscrowRecord(
      {required this.token, required this.inviteId, required this.expiresAt});
}

/// The pinned bulletin envelope carrying the escrow.
Uint8List buildEscrowEnvelope(
  Sodium sodium, {
  required InviteToken token,
  required int expiresAt,
  required int issuedAt,
  required int epoch,
  required Uint8List gk,
  required KeyPair senderSign,
}) =>
    sealEnvelope(
      sodium,
      type: 'ESCROW',
      fields: {
        't': b64(token.t),
        'inviteId': token.inviteId(sodium),
        'expiresAt': expiresAt,
      },
      issuedAt: issuedAt,
      epoch: epoch,
      gk: gk,
      senderSign: senderSign,
    );

/// Recover the escrowed token from an opened ESCROW envelope. Null if the
/// fields are malformed or the embedded inviteId does not derive from t —
/// a vandal cannot point an escrow at someone else's invite.
EscrowRecord? escrowFromEnvelope(Sodium sodium, OpenedEnvelope env) {
  if (env.type != 'ESCROW') return null;
  try {
    final t = b64decode(env.fields['t'] as String);
    if (t.length != 32) return null;
    final token = InviteToken(t);
    final claimedId = env.fields['inviteId'] as String;
    if (token.inviteId(sodium) != claimedId) return null;
    return EscrowRecord(
      token: token,
      inviteId: claimedId,
      expiresAt: env.fields['expiresAt'] as int,
    );
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Invite lifecycle state machine (§3.5 step 7): open → joined → granted,
// any pre-terminal state can void, "void — regenerate" is the universal
// recovery. No deeper machinery exists.
// ---------------------------------------------------------------------------

enum InviteStatus { open, joined, granted, voided }

class PendingInvite {
  final String inviteId;
  final Uint8List t;
  final int expiresAt;
  final InviteStatus status;

  const PendingInvite({
    required this.inviteId,
    required this.t,
    required this.expiresAt,
    required this.status,
  });

  bool isExpired(int nowSec) => nowSec > expiresAt;

  PendingInvite markJoined() => _to(InviteStatus.joined, from: InviteStatus.open);

  PendingInvite markGranted() =>
      _to(InviteStatus.granted, from: InviteStatus.joined);

  PendingInvite markVoided() {
    if (status == InviteStatus.granted || status == InviteStatus.voided) {
      throw StateError('cannot void a $status invite');
    }
    return _copy(InviteStatus.voided);
  }

  PendingInvite _to(InviteStatus next, {required InviteStatus from}) {
    if (status != from) {
      throw StateError('illegal invite transition $status to $next');
    }
    return _copy(next);
  }

  PendingInvite _copy(InviteStatus next) => PendingInvite(
      inviteId: inviteId, t: t, expiresAt: expiresAt, status: next);
}

/// "void — regenerate": one tap mints a genuinely fresh invite. The old
/// token stays dead; nothing is reused.
PendingInvite regenerateInvite(
  Sodium sodium,
  PendingInvite voided, {
  required int nowSec,
  required int ttlSeconds,
}) {
  final fresh = InviteToken.mint(sodium);
  return PendingInvite(
    inviteId: fresh.inviteId(sodium),
    t: fresh.t,
    expiresAt: nowSec + ttlSeconds,
    status: InviteStatus.open,
  );
}
