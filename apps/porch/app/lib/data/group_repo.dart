// group_repo — groups, rosters, epoch keys, folded state (BUILD-SPEC §2).
//
// A group is a purely client-side fact (§3.2 step 1): creation makes NO
// relay call. Membership ops seal as envelopes and ride the outbox; each op
// also folds OPTIMISTICALLY into local state — safe because the roster fold
// is idempotent, so the op's own echo from the bulletin is a no-op.
//
// Departures rotate (§3.6): the shared [performRotation] mints gk_{e+1},
// seals a bundle to every remaining member's mailbox, duplicates them on the
// OLD channel bulletin, and adopts locally — sync_service calls the same
// function when a fold makes THIS device the elected rotator.
import 'dart:typed_data';

import '../domain/domain.dart';
import 'env.dart';
import 'outbox.dart';
import 'porch_state.dart';
import 'relay_api.dart';

class GroupRepo {
  final PorchEnv _env;
  const GroupRepo(this._env);

  Future<PorchState> _load() async =>
      await _env.stateStore.load() ?? PorchState.initial();

  /// Create a group (incl. the onboarding "My Porch"): mint gk_1 locally,
  /// roster = [self as admin]. The server never learns this happened.
  Future<StoredGroup> createGroup(String name) async {
    final state = await _load();
    final now = _env.now();
    final me = RosterEntry(
      signPk: _env.identity.sign.publicKey,
      boxPk: _env.identity.box.publicKey,
      displayName: state.profile.displayName,
      contactNote: state.profile.contactNote,
      joinedAt: now,
      isAdmin: true,
    );
    final group = StoredGroup(
      groupUuid: b64urlNoPad(_env.sodium.randombytes.buf(16)),
      name: name,
      keys: [StoredEpochKey(epoch: 1, gk: mintGroupKey(_env.sodium))],
      roster: Roster.genesis(me),
    );
    state.groups.add(group);
    await _env.stateStore.save(state);
    return group;
  }

  /// Silent leave (§3.6 step 1): one signed LEAVE onto the bulletin, then
  /// local keys are wiped. Nothing notification-shaped exists to emit.
  /// Offline-safe: the sealed op waits in the outbox; the group is gone
  /// locally either way.
  Future<void> leaveGroup(String groupUuid) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    _enqueueRosterOp(state, g,
        type: 'LEAVE', fields: const {});
    state.groups.remove(g);
    state.presence.remove(groupUuid);
    await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
  }

  /// Start over, step one: leave every group, so this identity is in none.
  /// A backup file that leaks later then opens an identity no group holds.
  ///
  /// What is already queued goes first, so nothing this phone owed a group
  /// lands after its LEAVE. Then, for each group with someone else in it:
  /// every invite still open is voided and its link burned (the leaked
  /// file holds each one's token, and a later admin could still fulfil
  /// it), and the signed LEAVE is posted at once, not queued, so its
  /// result is known now. A posted LEAVE makes the remaining members'
  /// phones change the group key when they fold it (§3.6 step 2). A group
  /// that heard the LEAVE is forgotten here; one that did not is kept, so
  /// a later try can still tell it. A group with no one else in it needs
  /// no LEAVE and is kept for the wipe.
  ///
  /// Returns the names of the groups the LEAVE did not reach.
  Future<List<String>> leaveEveryGroup() async {
    final state = await _load();
    await Outbox.drain(state, _env.relay, now: _env.now());
    final me = _env.identity.sign.publicKey;
    final unreached = <String>[];
    for (final g in List.of(state.groups)) {
      if (g.roster.members.every((m) => bytesEqual(m.signPk, me))) continue;
      await voidAndBurnOutstandingInvites(_env, g);
      final kr = g.keyring();
      try {
        await _env.relay.bulletinPost(
          channelId: deriveChannelId(_env.sodium, kr.current.gk),
          slotId: deriveSlotId(_env.sodium, kr.current.gk, me),
          blob: sealEnvelope(
            _env.sodium,
            type: 'LEAVE',
            fields: const {},
            issuedAt: _env.now(),
            epoch: kr.current.epoch,
            gk: kr.current.gk,
            senderSign: _env.identity.sign,
          ),
        );
      } on RelayError {
        unreached.add(g.name);
        continue;
      }
      state.groups.remove(g);
      state.presence.remove(g.groupUuid);
    }
    await _env.stateStore.save(state);
    return unreached;
  }

  /// Admin removes a member → immediate rotation (§3.6 steps 1–3).
  Future<void> removeMember(String groupUuid,
      {required Uint8List memberPk}) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    if (!g.roster.isAdminPk(_env.identity.sign.publicKey)) {
      throw StateError('REMOVE requires admin');
    }
    if (!g.roster.isMember(memberPk)) {
      throw StateError('cannot remove a non-member');
    }
    final op = RemoveOp(
        senderSignPk: _env.identity.sign.publicKey,
        seq: 0,
        issuedAt: _env.now(),
        memberPk: memberPk);
    _enqueueRosterOp(state, g, type: op.type, fields: op.fields);
    g.roster = foldRoster(g.roster, [op]).roster;
    performRotation(_env, state, g);
    // REMOVAL is the hostile departure: the removed member still holds the
    // old key, so they can decrypt any outstanding invite's escrow and
    // recover its token — left redeemable, it would mint them a grant
    // carrying the NEW key. Void + burn so the token is useless. (LEAVE
    // deliberately does NOT void: the PRD gate-4 escrow rescue — a
    // successor admin fulfilling the leaver's orphaned invite — depends on
    // outstanding invites surviving a benign departure.)
    await voidAndBurnOutstandingInvites(_env, g);
    await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
  }

  /// Signed TRANSFER_ADMIN — no rotation (§3.7).
  Future<void> transferAdmin(String groupUuid,
      {required Uint8List toPk}) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    if (!g.roster.isAdminPk(_env.identity.sign.publicKey)) {
      throw StateError('TRANSFER_ADMIN requires admin');
    }
    final op = TransferAdminOp(
        senderSignPk: _env.identity.sign.publicKey,
        seq: 0,
        issuedAt: _env.now(),
        toPk: toPk);
    _enqueueRosterOp(state, g, type: op.type, fields: op.fields);
    g.roster = foldRoster(g.roster, [op]).roster;
    await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
  }

  /// Update the global profile and fan a signed PROFILE op to every group's
  /// bulletin (§3.7) — the plaintext exists only in state + E2EE envelopes.
  Future<void> updateProfile({String? displayName, String? contactNote}) async {
    final state = await _load();
    if (displayName != null) state.profile.displayName = displayName;
    if (contactNote != null) state.profile.contactNote = contactNote;
    for (final g in state.groups) {
      final op = ProfileOp(
          senderSignPk: _env.identity.sign.publicKey,
          seq: 0,
          issuedAt: _env.now(),
          displayName: displayName,
          contactNote: contactNote);
      _enqueueRosterOp(state, g, type: op.type, fields: op.fields);
      g.roster = foldRoster(g.roster, [op]).roster;
    }
    await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
  }

  /// Rotate a group whose roster has ALREADY dropped the departed member —
  /// the reactive path when a folded LEAVE/REMOVE elects this device
  /// (kept public for sync_service's tests; sync itself uses the shared
  /// helper against its own loaded state).
  Future<void> rotateAfterDeparture(String groupUuid,
      {required Uint8List departedPk}) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    performRotation(_env, state, g);
    await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
  }

  void _enqueueRosterOp(PorchState state, StoredGroup g,
      {required String type, required Map<String, Object?> fields}) {
    final kr = g.keyring();
    final blob = sealEnvelope(
      _env.sodium,
      type: type,
      fields: fields,
      issuedAt: _env.now(),
      epoch: kr.current.epoch,
      gk: kr.current.gk,
      senderSign: _env.identity.sign,
    );
    Outbox.enqueueBulletin(state, _env.sodium,
        gk: kr.current.gk,
        writerSignPk: _env.identity.sign.publicKey,
        blob: blob,
        now: _env.now());
  }

  StoredGroup _require(PorchState state, String groupUuid) {
    final g = state.groupByUuid(groupUuid);
    if (g == null) throw StateError('unknown group $groupUuid');
    return g;
  }
}

/// The one rotation implementation (§3.6 step 3), shared by GroupRepo
/// (proactive: admin removal) and SyncService (reactive: a folded departure
/// elected this device). [g.roster] must already be post-departure.
///
/// Mutates [state]: enqueues the sealed per-member mailbox blobs and the
/// old-channel bulletin duplicate onto the outbox, and adopts the new epoch
/// into [g]. The caller drains and saves. Rotation itself does NOT touch
/// outstanding invites — that is the caller's judgment: a hostile REMOVE
/// must [voidAndBurnOutstandingInvites], a benign LEAVE must not (gate 4).
///
/// Each mailbox post carries an independent 0–30 s jitter (§1.6/§3.6): the
/// anonymous fan-out POSTs must not land near-simultaneously, or a
/// live-compromised relay could infer co-membership from timing. The
/// bulletin duplicate is a single post and goes out immediately.
void performRotation(PorchEnv env, PorchState state, StoredGroup g) {
  final kr = g.keyring();
  final old = kr.current;
  final now = env.now();
  final newGk = mintGroupKey(env.sodium);
  final fanout = buildRotation(
    env.sodium,
    groupUuid: g.groupUuid,
    newEpoch: old.epoch + 1,
    newGk: newGk,
    postRoster: g.roster,
    rotatorSign: env.identity.sign,
    issuedAt: now,
    oldEpoch: old.epoch,
    oldGk: old.gk,
  );
  for (final e in fanout.mailboxBlobs.entries) {
    Outbox.enqueue(state,
        op: OutboxOp.mailbox,
        payload: {'mailboxId': e.key, 'blob': b64(e.value)},
        now: now,
        notBefore: now + env.nextRotationJitterSec());
  }
  Outbox.enqueueBulletin(state, env.sodium,
      gk: old.gk,
      writerSignPk: env.identity.sign.publicKey,
      blob: fanout.bulletinDupEnvelope,
      now: now);
  g.keys = StoredEpochKey.listFromKeyring(
      kr.adopt(epoch: old.epoch + 1, gk: newGk, nowSec: now));
}

/// A REMOVAL makes every outstanding invite unsafe: its token t is
/// escrowed on the bulletin encrypted under the OLD key (§3.5 step 2),
/// which the removed member still holds. Left alive, they could decrypt
/// the escrow, redeem the invite, and be GRANTED the new post-rotation key
/// — defeating the rotation. Rotation cannot un-publish the ciphertext, so
/// the token must become useless: every open/joined invite drops to the
/// terminal "void — regenerate" state (§3.5 step 7), which the inviter's
/// GroupDetail already surfaces. Returns the ids that were still open so
/// the caller can burn their relay join slot too.
List<String> voidOutstandingInvites(StoredGroup g) {
  final wereOpen = <String>[];
  for (var i = 0; i < g.pendingInvites.length; i++) {
    final invite = g.pendingInvites[i];
    if (invite.status == InviteStatus.open) wereOpen.add(invite.inviteId);
    if (invite.status == InviteStatus.open ||
        invite.status == InviteStatus.joined) {
      g.pendingInvites[i] = invite.markVoided();
    }
  }
  return wereOpen;
}

/// [voidOutstandingInvites], plus a best-effort foreground burn of each
/// still-open invite's relay join slot: posting a deliberately
/// undecryptable join blob consumes the one-time slot (§3.5 step 3 SET NX),
/// so the removed member's redeem gets 410 — and any OTHER device that
/// ingested the escrow and has not yet folded the REMOVE fetches the
/// garbage blob and voids via the existing vandal path in fulfillPending.
/// Failures are tolerated: the local void above is the load-bearing part,
/// and an already-consumed, expired, or unreachable slot changes nothing.
Future<void> voidAndBurnOutstandingInvites(PorchEnv env, StoredGroup g) async {
  for (final inviteId in voidOutstandingInvites(g)) {
    try {
      await env.relay.joinInvite(inviteId: inviteId, blob: Uint8List(1));
    } on RelayError {
      // Best-effort by design — see doc comment.
    }
  }
}
