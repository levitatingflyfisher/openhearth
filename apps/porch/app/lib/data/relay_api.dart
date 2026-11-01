// RelayApi — the typed surface of the blind relay (BUILD-SPEC §4).
//
// This interface is the data layer's ONLY door to the network. Two
// structural rules are visible right in the signatures:
//   - Channel-plane methods (§4 rows 8–11) take capabilities only — there is
//     no parameter through which identity material could reach a /v1/ch/*
//     request. Knowledge of the channelId IS the auth.
//   - The single authenticated call (mailbox drain) takes a pre-built
//     [DrainAuth] value: one stateless Ed25519 signature, no sessions, no
//     tokens, no challenge flow.
//
// Implementations: [HttpRelayApi] (api_client.dart) over dart:io, and
// [FakeRelay] (fake_relay.dart) with the exact server semantics for tests.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show KeyPair, Sodium;

import '../domain/domain.dart' show b64, b64decode;

// ---------------------------------------------------------------------------
// Typed errors. The relay answers bare status codes (no bodies, no detail —
// §4); the client gives each one a name so repositories can branch without
// matching on ints. RelayUnreachable is the offline case the outbox absorbs.
// ---------------------------------------------------------------------------

sealed class RelayError implements Exception {
  final String message;
  const RelayError(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// Network-level failure: refused, DNS, timeout. The request may or may not
/// have been received — callers must treat delivery as UNKNOWN (which is why
/// only protocol-idempotent operations are ever retried).
class RelayUnreachable extends RelayError {
  const RelayUnreachable(super.message);
}

/// 404 — unknown or expired capability.
class RelayNotFound extends RelayError {
  const RelayNotFound() : super('not found (unknown or expired)');
}

/// 410 — one-time resource already consumed (invite join).
class RelayGone extends RelayError {
  const RelayGone() : super('gone (already consumed)');
}

/// 409 — id already exists (invite create).
class RelayConflict extends RelayError {
  const RelayConflict() : super('conflict (id exists)');
}

/// 401 — drain signature rejected.
class RelayUnauthorized extends RelayError {
  const RelayUnauthorized() : super('unauthorized');
}

/// 429 — rate limited, or mailbox/pin capacity reached.
class RelayRateLimited extends RelayError {
  const RelayRateLimited() : super('rate limited or full');
}

/// 413 — blob exceeds the relay's hard size cap.
class RelayTooLarge extends RelayError {
  const RelayTooLarge() : super('blob exceeds relay cap');
}

/// 400 — the relay rejected the request shape. A client bug.
class RelayBadRequest extends RelayError {
  const RelayBadRequest() : super('bad request (client bug)');
}

/// 5xx — the relay itself failed.
class RelayServerError extends RelayError {
  final int status;
  const RelayServerError(this.status) : super('server error');
}

/// 2xx arrived but the body was not the documented shape.
class RelayProtocolError extends RelayError {
  const RelayProtocolError(super.message);
}

/// Map a non-2xx status to its typed error (§4 + router.go storeErrStatus).
RelayError relayErrorForStatus(int status) => switch (status) {
      404 => const RelayNotFound(),
      410 => const RelayGone(),
      409 => const RelayConflict(),
      401 => const RelayUnauthorized(),
      429 => const RelayRateLimited(),
      413 => const RelayTooLarge(),
      400 => const RelayBadRequest(),
      _ => RelayServerError(status),
    };

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

/// One TTL'd presence slot as fetched (§4 row 9).
class PresenceSlot {
  final String slotId;
  final Uint8List blob;
  final int expiresAt;
  const PresenceSlot(
      {required this.slotId, required this.blob, required this.expiresAt});
}

/// One bulletin entry (§4 row 11). [expiresAt] is present for pinned entries
/// only; unpinned entries live on the ring's sliding TTL.
class BulletinEntry {
  final int seq;
  final Uint8List blob;
  final bool pinned;
  final int? expiresAt;
  const BulletinEntry(
      {required this.seq,
      required this.blob,
      required this.pinned,
      this.expiresAt});
}

/// The stateless drain credential (§4 row 7): pubkey + timestamp + one
/// Ed25519 signature over "porch-drain|{mailboxId}|{ts}". Nothing about it
/// persists server-side beyond a 10-minute replay cache on hash(sig).
class DrainAuth {
  final Uint8List pubkey;
  final int ts;
  final Uint8List sig;
  const DrainAuth({required this.pubkey, required this.ts, required this.sig});

  Map<String, Object?> toJson() =>
      {'pubkey': b64(pubkey), 'ts': ts, 'sig': b64(sig)};
}

/// Sign a drain request. The message format is pinned by the relay's
/// sigauth_test.go: "porch-drain|" + mailboxId + "|" + ts.
DrainAuth buildDrainAuth(
  Sodium sodium, {
  required KeyPair sign,
  required String mailboxId,
  required int ts,
}) =>
    DrainAuth(
      pubkey: Uint8List.fromList(sign.publicKey),
      ts: ts,
      sig: sodium.crypto.sign.detached(
        message: Uint8List.fromList(utf8.encode('porch-drain|$mailboxId|$ts')),
        secretKey: sign.secretKey,
      ),
    );

// ---------------------------------------------------------------------------
// The interface
// ---------------------------------------------------------------------------

abstract interface class RelayApi {
  // --- invites (§4 rows 1–5) ---

  /// Register [inviteId] (the token t NEVER travels). Returns expiresAt.
  /// Throws [RelayConflict] if the id exists.
  Future<int> createInvite({required String inviteId, required int ttlHours});

  /// Bob's one-time join. Throws [RelayGone] when already consumed.
  Future<void> joinInvite({required String inviteId, required Uint8List blob});

  /// Fulfiller fetches Bob's intro blob, gated on fetchProof.
  Future<Uint8List> fetchJoin(
      {required String inviteId, required String proof});

  /// Fulfiller posts the sealed grant, gated on fetchProof.
  Future<void> putGrant(
      {required String inviteId, required String proof, required Uint8List blob});

  /// Bob takes the grant (server deletes it after retrieval), gated on
  /// grantProof.
  Future<Uint8List> takeGrant(
      {required String inviteId, required String proof});

  // --- mailbox (§4 rows 6–7) ---

  /// Anonymous by design — no identity parameter exists.
  Future<void> mailboxPost({required String mailboxId, required Uint8List blob});

  /// Stateless signed drain. Atomic: returned == deleted.
  Future<List<Uint8List>> mailboxDrain(
      {required String mailboxId, required DrainAuth auth});

  // --- channel plane (§4 rows 8–11): capabilities only, no identity ---

  Future<void> presencePost(
      {required String channelId,
      required String slotId,
      required Uint8List blob,
      required int ttlSec});

  Future<List<PresenceSlot>> presenceGet(String channelId);

  /// Returns the server-assigned monotonic per-channel seq. Unpinned entries
  /// must send ttlSec 0 (the ring owns their lifetime); pinned entries carry
  /// their own TTL. [slotId] names the writer by its bulletin writer id in
  /// the channel's epoch (deriveBulletinWriterId, never its presence slot
  /// id): the relay keeps only whether a second writer has written, so a
  /// channel written only by bulletin can hold its place.
  Future<int> bulletinPost(
      {required String channelId,
      required Uint8List blob,
      bool pinned = false,
      int ttlSec = 0,
      String? slotId});

  Future<List<BulletinEntry>> bulletinGet(String channelId, {int afterSeq = 0});

  // --- ops (§4 row 12) ---

  Future<bool> healthz();
}

// ---------------------------------------------------------------------------
// Shared response decoding (used by HttpRelayApi and exercised against both
// implementations). Blob JSON fields are standard base64 — the Go
// encoding/json []byte convention.
// ---------------------------------------------------------------------------

Uint8List decodeBlobField(Map<String, Object?> body, String key) {
  final v = body[key];
  if (v is! String) throw RelayProtocolError('missing/invalid "$key"');
  try {
    return b64decode(v);
  } on FormatException {
    throw RelayProtocolError('field "$key" is not base64');
  }
}
