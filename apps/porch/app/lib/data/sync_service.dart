// sync_service — RefreshFeed (§3.4 step 5), the one pipeline that moves
// relay bytes into honest local state. Strict order per group:
//
//   flush outbox → bulletin fold by seq (grace channel first, then current)
//   → signed mailbox drain → rotation adoption → rekey answers → presence
//   decode on the (possibly new) channels → PresenceSnapshot(fetchedAt: now)
//   → save → widget mirror.
//
// Ordering matters twice: roster ops MUST fold before presence decode (a
// just-joined member's events would otherwise drop as foreign), and
// rotation grants MUST apply before the next poll so it uses the new
// channelId.
//
// Offline honesty: a group whose reads fail keeps its previous snapshot and
// its previous fetchedAt — the staleness line renders instead of a lie.
//
// Channel polling: the CURRENT channel pages by lastBulletinSeq; the GRACE
// channel (7-day decrypt window after rotation) is always polled from seq 0
// — it is low-traffic by construction, folds are idempotent, and this is
// what lets a REKEY_REQUEST posted after total relay loss (seq reset) still
// be seen by rotated members. Total loss on the CURRENT channel remains the
// spec's accepted degradation (§5.4).
import 'dart:typed_data';

import '../domain/domain.dart';
import 'env.dart';
import 'group_repo.dart' show performRotation, voidAndBurnOutstandingInvites;
import 'outbox.dart';
import 'porch_state.dart';
import 'relay_api.dart';
import 'widget_cache.dart';

class SyncService {
  final PorchEnv _env;
  final WidgetCacheMirror _widgetMirror;

  /// Groups with an outstanding REKEY_REQUEST from THIS device: re-grants
  /// of an existing epoch are only trusted when we actually asked (§3.6
  /// step 4 / domain validateRotation selfHeal gate).
  final _selfHealPending = <String>{};

  /// Hashes of rekey-request envelopes already answered this session, so a
  /// pinned/lingering request is not re-granted on every poll.
  final _answeredRekeys = <String>{};

  int _lastDrainTs = 0;

  SyncService(this._env, {WidgetCacheMirror? widgetMirror})
      : _widgetMirror = widgetMirror ?? const NoopWidgetCacheMirror();

  Future<void> refreshFeed() async {
    final state = await _env.stateStore.load();
    if (state == null) return; // nothing to sync before onboarding
    final now = _env.now();

    // 0. Flush queued writes first so reads below see our own events.
    await Outbox.drain(state, _env.relay, now: now);

    final rotationCandidates = <String, List<RotationCandidate>>{};
    final rekeyRequests = <String, List<(RekeyRequest, String)>>{};
    final readFailed = <String>{};

    // 1. Bulletins: fold roster ops in seq order; collect rotation dups,
    //    escrows, rekey requests. Grace channel first — its ops predate
    //    everything on the current channel.
    for (final g in state.groups) {
      _pruneKeyring(g, now);
      var kr = g.keyring();
      // Grace first (its ops predate the current channel), then current.
      // The CURRENT channel pages server-side by its cursor; the GRACE
      // channel is fetched from seq 0 so cursor-independent artifacts
      // (ROTATION dups, ESCROWs, REKEY_REQUESTs — all epoch- or
      // id-deduplicated) survive even a relay wipe that reset the seq
      // counter. Roster ops, whose fold is NOT replay-safe across
      // rotations, fold strictly above the stored cursor on BOTH channels.
      final channels = <({String chId, bool fetchAll})>[
        if (kr.decryptable.length > 1)
          (
            chId: deriveChannelId(_env.sodium, kr.decryptable.last.gk),
            fetchAll: true,
          ),
        (chId: deriveChannelId(_env.sodium, kr.current.gk), fetchAll: false),
      ];
      for (final ch in channels) {
        final cursorAtStart = g.lastBulletinSeq[ch.chId] ?? 0;
        final List<BulletinEntry> entries;
        try {
          entries = await _env.relay
              .bulletinGet(ch.chId, afterSeq: ch.fetchAll ? 0 : cursorAtStart);
        } on RelayError {
          readFailed.add(g.groupUuid);
          continue;
        }
        entries.sort((a, b) => a.seq - b.seq);
        for (final entry in entries) {
          if (entry.seq > (g.lastBulletinSeq[ch.chId] ?? 0)) {
            g.lastBulletinSeq[ch.chId] = entry.seq;
          }
          final env =
              openEnvelope(_env.sodium, wire: entry.blob, keyring: kr);
          if (env == null) continue; // vandal bytes vanish silently
          switch (env.type) {
            case 'ROTATION':
              final bundle = rotationFromDupEnvelope(_env.sodium,
                  env: env,
                  myBox: _env.identity.box,
                  mySignPk: _env.identity.sign.publicKey);
              if (bundle != null) {
                (rotationCandidates[bundle.groupUuid] ??= []).add(
                    RotationCandidate(bundle: bundle, seq: entry.seq));
              }
            case 'ESCROW':
              _ingestEscrow(g, env);
            case 'REKEY_REQUEST':
              final req = rekeyRequestFromEnvelope(env, roster: g.roster);
              if (req != null) {
                (rekeyRequests[g.groupUuid] ??= [])
                    .add((req, _hashOf(entry.blob)));
              }
            default:
              if (entry.seq > cursorAtStart) {
                kr = await _foldRosterOp(state, g, env, entry.seq, kr);
              }
          }
        }
      }
    }

    // 2. One signed mailbox drain (ts strictly monotonic: Ed25519 is
    //    deterministic, so a same-second re-drain would trip the relay's
    //    replay cache).
    var ts = now;
    if (ts <= _lastDrainTs) ts = _lastDrainTs + 1;
    _lastDrainTs = ts;
    List<Uint8List> mail = const [];
    try {
      mail = await _env.relay.mailboxDrain(
        mailboxId: _env.identity.mailboxId,
        auth: buildDrainAuth(_env.sodium,
            sign: _env.identity.sign,
            mailboxId: _env.identity.mailboxId,
            ts: ts),
      );
    } on RelayError {
      // Offline or refused: grants stay queued server-side for next drain.
    }
    for (final blob in mail) {
      final bundle = openRotationBundle(_env.sodium,
          myBox: _env.identity.box, sealed: blob);
      if (bundle != null) {
        (rotationCandidates[bundle.groupUuid] ??= [])
            .add(RotationCandidate(bundle: bundle));
      }
      // Anything else in the mailbox is not ours to understand — dropped.
    }

    // 3. Adopt rotations: validate, then the deterministic winner.
    for (final g in state.groups) {
      final candidates = [
        for (final c in rotationCandidates[g.groupUuid] ?? <RotationCandidate>[])
          if (c.bundle.epoch > g.epoch &&
              validateRotation(c.bundle,
                  localRoster: g.roster,
                  currentEpoch: g.epoch,
                  selfHeal: _selfHealPending.contains(g.groupUuid)))
            c,
      ];
      final winner = electRotationWinner(_env.sodium, candidates);
      if (winner == null) continue;
      g.keys = StoredEpochKey.listFromKeyring(g.keyring().adopt(
          epoch: winner.bundle.epoch, gk: winner.bundle.gk, nowSec: now));
      g.roster = winner.bundle.roster;
      _selfHealPending.remove(g.groupUuid);
    }

    // 4. Answer valid rekey requests with a re-grant of the CURRENT epoch,
    //    sealed to the roster-verified box key (§3.6 step 6).
    for (final g in state.groups) {
      for (final (req, hash) in rekeyRequests[g.groupUuid] ??
          const <(RekeyRequest, String)>[]) {
        if (_answeredRekeys.contains(hash)) continue;
        if (bytesEqual(req.requesterSignPk, _env.identity.sign.publicKey)) {
          continue; // my own request
        }
        final kr = g.keyring();
        final regrant = buildRegrant(
          _env.sodium,
          request: req,
          groupUuid: g.groupUuid,
          currentEpoch: kr.current.epoch,
          currentGk: kr.current.gk,
          roster: g.roster,
          responderSign: _env.identity.sign,
          issuedAt: now,
        );
        Outbox.enqueue(state,
            op: OutboxOp.mailbox,
            payload: {
              'mailboxId':
                  deriveMailboxId(_env.sodium, req.requesterSignPk),
              'blob': b64(regrant),
            },
            now: now);
        _answeredRekeys.add(hash);
      }
    }

    // 5. Presence: decode on the (possibly new) current channel + grace,
    //    fold to a snapshot stamped with THIS fetch. Groups whose reads
    //    failed keep their previous snapshot and honest fetchedAt.
    for (final g in state.groups) {
      if (readFailed.contains(g.groupUuid)) continue;
      final kr = g.keyring();
      final blobs = <Uint8List>[];
      var ok = true;
      for (final ek in kr.decryptable) {
        try {
          final slots = await _env.relay
              .presenceGet(deriveChannelId(_env.sodium, ek.gk));
          blobs.addAll([for (final s in slots) s.blob]);
        } on RelayError {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      state.presence[g.groupUuid] = foldPresenceFeed(
        _env.sodium,
        blobs: blobs,
        keyring: kr,
        roster: g.roster,
        now: now,
        fetchedAt: now,
      );
    }

    // 6. Send what this refresh produced (rotations, re-grants), persist,
    //    mirror the widget cache.
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
    await _widgetMirror.write(buildWidgetCacheSnapshot(state,
        myPk: _env.identity.sign.publicKey, fallbackFetchedAt: now));
  }

  /// Post a REKEY_REQUEST on the group's current channel (§3.6 step 6) and
  /// arm the self-heal gate so the next re-grant of a newer epoch is
  /// trusted from any roster member.
  Future<void> requestSelfHeal(String groupUuid) async {
    final state = await _env.stateStore.load();
    if (state == null) return;
    final g = state.groupByUuid(groupUuid);
    if (g == null) throw StateError('unknown group $groupUuid');
    final now = _env.now();
    final kr = g.keyring();
    final blob = buildRekeyRequestEnvelope(
      _env.sodium,
      myBoxPk: _env.identity.box.publicKey,
      issuedAt: now,
      epoch: kr.current.epoch,
      gk: kr.current.gk,
      senderSign: _env.identity.sign,
    );
    Outbox.enqueueBulletin(state, _env.sodium,
        gk: kr.current.gk,
        writerSignPk: _env.identity.sign.publicKey,
        blob: blob,
        now: now);
    _selfHealPending.add(groupUuid);
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
  }

  /// Fold one roster envelope; when an ACCEPTED departure elects this
  /// device, rotate immediately (§3.6 step 2). Returns the group's keyring,
  /// refreshed if rotation advanced it.
  Future<GroupKeyring> _foldRosterOp(PorchState state, StoredGroup g,
      OpenedEnvelope env, int seq, GroupKeyring kr) async {
    final op = rosterOpFromEnvelope(env, seq: seq);
    if (op == null) return kr;
    final departedPk = departureOf(op);
    final preRoster = g.roster;
    final wasMember =
        departedPk == null ? false : preRoster.isMember(departedPk);
    g.roster = foldRoster(preRoster, [op]).roster;
    if (departedPk == null || !wasMember) return kr;
    if (g.roster.isMember(departedPk)) return kr; // fold rejected it
    if (op is RemoveOp) {
      // Hostile departure: the removed member still holds the old key and
      // can decrypt any outstanding invite's escrow — were the invite left
      // fulfillable on THIS device, they could redeem it and be granted
      // the post-rotation key. Void + burn on every device that folds the
      // REMOVE, rotator or not. (A folded LEAVE deliberately keeps
      // invites alive: gate 4's escrow rescue depends on it.)
      await voidAndBurnOutstandingInvites(_env, g);
    }
    final rotator = electRotator(preRoster, departedPk: departedPk);
    final me = _env.identity.sign.publicKey;
    if (rotator != null &&
        bytesEqual(rotator, me) &&
        !bytesEqual(departedPk, me)) {
      performRotation(_env, state, g);
      return g.keyring();
    }
    return kr;
  }

  /// Escrow ingestion (§3.5 step 2 / PRD gate 4): a pinned ESCROW from a
  /// (then-)member makes the invite fulfillable by whoever remains. Any
  /// already-known inviteId — open, granted or voided — blocks re-ingest.
  void _ingestEscrow(StoredGroup g, OpenedEnvelope env) {
    if (!g.roster.isMember(env.senderSignPk)) return;
    final escrow = escrowFromEnvelope(_env.sodium, env);
    if (escrow == null) return;
    if (g.pendingInvites.any((i) => i.inviteId == escrow.inviteId)) return;
    g.pendingInvites.add(PendingInvite(
      inviteId: escrow.inviteId,
      t: escrow.token.t,
      expiresAt: escrow.expiresAt,
      status: InviteStatus.open,
    ));
  }

  void _pruneKeyring(StoredGroup g, int now) {
    final kr = g.keyring();
    final pruned = kr.prune(now);
    if (pruned.keys.length != kr.keys.length) {
      g.keys = StoredEpochKey.listFromKeyring(pruned);
      // Bulletin cursors for channels we can no longer decrypt are dead
      // weight; keep only cursors for keys we still hold.
      final live = {
        for (final ek in pruned.keys) deriveChannelId(_env.sodium, ek.gk),
      };
      g.lastBulletinSeq.removeWhere((chId, _) => !live.contains(chId));
    }
  }

  String _hashOf(Uint8List blob) =>
      b64(_env.sodium.crypto.genericHash(message: blob, outLen: 16));
}
