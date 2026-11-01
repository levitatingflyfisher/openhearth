// Presence (BUILD-SPEC §3.4): encrypt → route → TTL.
//
// A presence event is an ordinary envelope (type "presence") posted to the
// member's KDF-derived slot with a native server TTL — presence structurally
// cannot exist after expiry. "Off" is a short-lived signed tombstone, not a
// delete endpoint. The feed fold is verify → roster-check → dedupe (highest
// issuedAt per member) → drop-expired; unverifiable bytes vanish silently.
//
// PresenceSnapshot is the typed-honesty artifact (§1.4): it CANNOT be
// constructed without fetchedAt — there is no default, so no rendering layer
// can ever hold presence data without knowing how old it is.
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'envelope.dart';
import 'keyring.dart';
import 'roster.dart';
import 'support/bytes.dart';

/// Relay cap for presence slot TTLs (§4 row 8, §5.4).
const int presenceMaxTtlSeconds = 14700;

/// Tombstone TTL: pollers drop the row within one cycle, then it evaporates.
const int presenceOffTtlSeconds = 60;

/// Relay cap for presence blobs (§4 row 8).
const int presenceMaxBlobBytes = 1024;

/// Feed/widget staleness threshold (§1.4): older than this renders
/// "as of N min ago".
const int snapshotStaleSeconds = 15 * 60;

/// Everything needed to POST /v1/ch/{channelId}/presence.
class PresencePost {
  final String channelId;
  final String slotId;
  final Uint8List blob;
  final int ttlSec;
  const PresencePost({
    required this.channelId,
    required this.slotId,
    required this.blob,
    required this.ttlSec,
  });
}

/// One live friend in the feed (§5.2 presence shape).
class PresenceEntry {
  final Uint8List memberSignPk;
  final String tag;
  final int issuedAt;
  final int expiresAt;
  const PresenceEntry({
    required this.memberSignPk,
    required this.tag,
    required this.issuedAt,
    required this.expiresAt,
  });
}

/// The ONLY shape presence reaches a renderer in. [fetchedAt] is required
/// by construction — honesty is typed, not remembered.
class PresenceSnapshot {
  final List<PresenceEntry> entries;
  final int fetchedAt;

  PresenceSnapshot({required List<PresenceEntry> entries, required this.fetchedAt})
      : entries = List.unmodifiable(entries);

  /// True when a UI must render the staleness line instead of pretending.
  bool isStaleAt(int nowSec) => nowSec - fetchedAt > snapshotStaleSeconds;
}

/// Tap Available (§3.4 step 1–2): build the encrypted slot write.
PresencePost encodePresenceOn(
  Sodium sodium, {
  required GroupKeyring keyring,
  required KeyPair senderSign,
  required String tag,
  required int now,
  required int expiresAt,
}) {
  if (expiresAt <= now) {
    throw ArgumentError.value(expiresAt, 'expiresAt', 'must be in the future');
  }
  return _encode(
    sodium,
    keyring: keyring,
    senderSign: senderSign,
    fields: {'status': 'on', 'tag': tag, 'expiresAt': expiresAt},
    now: now,
    ttlSec: (expiresAt - now).clamp(1, presenceMaxTtlSeconds),
  );
}

/// Manual off (§3.4 step 4): overwrite own slot with a 60 s tombstone.
PresencePost encodePresenceOff(
  Sodium sodium, {
  required GroupKeyring keyring,
  required KeyPair senderSign,
  required int now,
}) =>
    _encode(
      sodium,
      keyring: keyring,
      senderSign: senderSign,
      fields: {'status': 'off', 'tag': '', 'expiresAt': now},
      now: now,
      ttlSec: presenceOffTtlSeconds,
    );

PresencePost _encode(
  Sodium sodium, {
  required GroupKeyring keyring,
  required KeyPair senderSign,
  required Map<String, Object?> fields,
  required int now,
  required int ttlSec,
}) {
  final current = keyring.current;
  final blob = sealEnvelope(
    sodium,
    type: 'presence',
    fields: fields,
    issuedAt: now,
    epoch: current.epoch,
    gk: current.gk,
    senderSign: senderSign,
  );
  if (blob.length > presenceMaxBlobBytes) {
    throw ArgumentError(
        'presence blob ${blob.length} B exceeds the $presenceMaxBlobBytes B '
        'relay cap — shorten the tag');
  }
  return PresencePost(
    channelId: deriveChannelId(sodium, current.gk),
    slotId: deriveSlotId(sodium, current.gk, senderSign.publicKey),
    blob: blob,
    ttlSec: ttlSec,
  );
}

/// Fold fetched slot blobs into a snapshot (§3.4 step 5):
/// decrypt/verify (envelope) → roster membership → dedupe keeping the
/// highest issuedAt per member → drop offs and expired. Unverifiable or
/// foreign blobs are dropped without a trace — a vandal can stomp slots
/// (bounded by rotation) but can never forge a friend.
PresenceSnapshot foldPresenceFeed(
  Sodium sodium, {
  required List<Uint8List> blobs,
  required GroupKeyring keyring,
  required Roster roster,
  required int now,
  required int fetchedAt,
}) {
  // Newest event per member, by issuedAt.
  final newest = <String, OpenedEnvelope>{};
  for (final blob in blobs) {
    final env = openEnvelope(sodium, wire: blob, keyring: keyring);
    if (env == null) continue;
    if (env.type != 'presence') continue;
    if (!roster.isMember(env.senderSignPk)) continue;
    final key = b64(env.senderSignPk);
    final seen = newest[key];
    if (seen == null || env.issuedAt > seen.issuedAt) newest[key] = env;
  }

  final entries = <PresenceEntry>[];
  for (final env in newest.values) {
    final status = env.fields['status'];
    final tag = env.fields['tag'];
    final expiresAt = env.fields['expiresAt'];
    if (status != 'on' || tag is! String || expiresAt is! int) continue;
    if (expiresAt <= now) continue; // already over
    entries.add(PresenceEntry(
      memberSignPk: env.senderSignPk,
      tag: tag,
      issuedAt: env.issuedAt,
      expiresAt: expiresAt,
    ));
  }
  // Stable, deterministic order for rendering and tests alike.
  entries.sort((a, b) {
    final d = b.issuedAt - a.issuedAt;
    if (d != 0) return d;
    return b64(a.memberSignPk).compareTo(b64(b.memberSignPk));
  });
  return PresenceSnapshot(entries: entries, fetchedAt: fetchedAt);
}
