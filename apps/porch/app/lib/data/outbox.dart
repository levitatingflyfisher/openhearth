// Outbox — the write-behind queue that makes every mutation offline-first
// (§3.4 step 1 "optimistic outbox-first"; §5.2 outbox).
//
// RETRY-SAFETY IS PROTOCOL-LEVEL, NOT HTTP-LEVEL. The HTTP client never
// retries (an ambiguous failure means delivery is UNKNOWN); the outbox may
// redeliver, which is safe because every op we queue is idempotent or
// replay-tolerated at the RECEIVING end:
//   - presence: slot overwrite — redelivery re-writes the same slot;
//   - bulletin: roster-op folds are idempotent; rotation dups and escrows
//     dedupe on adoption/inviteId (a duplicate pinned escrow costs one pin
//     slot until its TTL — accepted, bounded by the 16-pin cap);
//   - mailbox: rotation bundles/re-grants are epoch-guarded on adoption.
// Invite create/join are NOT queued — they are one-time consumptions whose
// errors the user must see; invite_repo runs them foreground.
//
// Drain policy: FIFO. Transient failures (unreachable, 429, 5xx) keep the
// entry, count the attempt, and STOP the drain (preserves cross-entry
// ordering). Permanent rejections (4xx) drop the entry — retrying a 413
// forever would wedge the queue behind a poison blob.
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show Sodium;

import '../domain/domain.dart'
    show
        b64,
        b64decode,
        deriveBulletinWriterId,
        deriveChannelId,
        presenceMaxTtlSeconds;
import 'porch_state.dart';
import 'relay_api.dart';

abstract final class Outbox {
  static int _counter = 0;

  /// Queue [payload] onto [state] (caller persists). Payload blobs are
  /// standard base64 strings, matching the state file's JSON conventions.
  /// [notBefore] (unix seconds) holds delivery until then — rotation
  /// fan-out jitter (§3.6); 0 = due immediately.
  static void enqueue(
    PorchState state, {
    required OutboxOp op,
    required Map<String, Object?> payload,
    required int now,
    int notBefore = 0,
  }) {
    state.outbox.add(OutboxEntry(
      id: '$now-${_counter++}',
      op: op,
      payload: payload,
      createdAt: now,
      notBefore: notBefore,
    ));
  }

  /// The one way a bulletin write is queued: onto [gk]'s channel, naming
  /// the writer by [writerSignPk]'s bulletin writer id in that epoch (not
  /// its presence slot id, so the relay cannot tie the two). The relay
  /// counts a channel as confirmed once a second writer writes there, so a
  /// group that only writes bulletins keeps its place (relay
  /// ChannelFreshTTL). The wire field is still `slotId`: the relay checks
  /// only that it is an id. [ttlSec] is for pinned entries only.
  static void enqueueBulletin(
    PorchState state,
    Sodium sodium, {
    required Uint8List gk,
    required Uint8List writerSignPk,
    required Uint8List blob,
    bool pinned = false,
    int ttlSec = 0,
    required int now,
  }) =>
      enqueue(state,
          op: OutboxOp.bulletin,
          payload: {
            'channelId': deriveChannelId(sodium, gk),
            'slotId': deriveBulletinWriterId(sodium, gk, writerSignPk),
            'blob': b64(blob),
            if (pinned) 'pinned': true,
            if (pinned) 'ttlSec': ttlSec,
          },
          now: now);

  /// Deliver queued entries in order. Mutates [state]; the caller saves.
  /// Returns the number of entries still queued (0 = fully drained).
  /// Never throws for delivery failures — offline is a normal state.
  ///
  /// Entries with `notBefore > now` are HELD: skipped silently (no attempt
  /// counted) while later due entries still deliver. Only jittered rotation
  /// mailbox posts carry a future notBefore, and those are epoch-guarded
  /// and self-contained — being overtaken by a later bulletin/presence
  /// post is harmless, so jitter never blocks the optimistic tap path.
  static Future<int> drain(
    PorchState state,
    RelayApi relay, {
    required int now,
  }) async {
    for (final entry in List.of(state.outbox)) {
      if (entry.notBefore > now) continue; // jittered: not due yet
      try {
        final deliverable = await _deliver(entry, relay, now);
        // Delivered — or intentionally skipped (e.g. expired presence).
        state.outbox.remove(entry);
        if (!deliverable) continue;
      } on RelayUnreachable {
        entry.attempts++;
        break; // offline: stop, keep order
      } on RelayRateLimited {
        entry.attempts++;
        break; // back off: stop, keep order
      } on RelayServerError {
        entry.attempts++;
        break; // relay trouble: stop, keep order
      } on RelayError {
        state.outbox.remove(entry); // permanent rejection: poison, drop
      } on FormatException {
        state.outbox.remove(entry); // unparseable payload: poison, drop
      }
    }
    return state.outbox.length;
  }

  /// Returns false when the entry was consciously NOT sent (stale).
  static Future<bool> _deliver(
      OutboxEntry entry, RelayApi relay, int now) async {
    final p = entry.payload;
    switch (entry.op) {
      case OutboxOp.presence:
        // ttl is recomputed at DELIVERY time from the absolute expiry —
        // an event that expired while queued must never be resurrected.
        final expiresAt = p['expiresAt'] as int;
        final ttlSec = expiresAt - now;
        if (ttlSec <= 0) return false;
        await relay.presencePost(
          channelId: p['channelId'] as String,
          slotId: p['slotId'] as String,
          blob: b64decode(p['blob'] as String),
          ttlSec: ttlSec.clamp(1, presenceMaxTtlSeconds),
        );
      case OutboxOp.bulletin:
        await relay.bulletinPost(
          channelId: p['channelId'] as String,
          blob: b64decode(p['blob'] as String),
          pinned: p['pinned'] as bool? ?? false,
          ttlSec: p['ttlSec'] as int? ?? 0,
          slotId: p['slotId'] as String?,
        );
      case OutboxOp.mailbox:
        await relay.mailboxPost(
          mailboxId: p['mailboxId'] as String,
          blob: b64decode(p['blob'] as String),
        );
    }
    return true;
  }
}
