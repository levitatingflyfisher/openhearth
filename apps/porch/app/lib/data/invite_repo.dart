// invite_repo — the §3.5 handshake wired to relay + storage:
// mint → (escrow) → redeem → fulfill → complete, plus void — regenerate.
//
// Invite create/join/grant run FOREGROUND, not through the outbox: they are
// one-time consumptions whose typed errors ("that invite was already used")
// the user must see immediately. Only the escrow pin and the JOIN announce —
// idempotent bulletin ops — ride the outbox.
import 'dart:typed_data';

import '../domain/domain.dart';
import 'env.dart';
import 'outbox.dart';
import 'porch_state.dart';
import 'relay_api.dart';

/// What the inviter shows/shares. The token never touches the server.
class InviteHandle {
  final String inviteId;
  final String link;
  final String code;
  final InviteToken token;
  const InviteHandle(
      {required this.inviteId,
      required this.link,
      required this.code,
      required this.token});
}

/// Bob's side of a redeemed invite, held until the grant arrives.
/// In-memory only: if the app dies before completion, the invite burns and
/// the inviter regenerates — the universal recovery (§3.5 step 7).
class JoinedInvite {
  final String inviteId;
  final InviteToken token;
  const JoinedInvite({required this.inviteId, required this.token});
}

class InviteRepo {
  final PorchEnv _env;
  const InviteRepo(this._env);

  Future<PorchState> _load() async =>
      await _env.stateStore.load() ?? PorchState.initial();

  /// Alice mints (§3.5 steps 1–2): register inviteId (foreground — needs
  /// the relay by nature), pin the group-encrypted escrow, persist the
  /// pending invite. On relay failure nothing is persisted.
  Future<InviteHandle> mint(String groupUuid, {int ttlHours = 72}) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    final token = InviteToken.mint(_env.sodium);
    final inviteId = token.inviteId(_env.sodium);
    final now = _env.now();

    final expiresAt = await _env.relay
        .createInvite(inviteId: inviteId, ttlHours: ttlHours); // may throw

    final kr = g.keyring();
    final escrow = buildEscrowEnvelope(
      _env.sodium,
      token: token,
      expiresAt: expiresAt,
      issuedAt: now,
      epoch: kr.current.epoch,
      gk: kr.current.gk,
      senderSign: _env.identity.sign,
    );
    Outbox.enqueueBulletin(state, _env.sodium,
        gk: kr.current.gk,
        writerSignPk: _env.identity.sign.publicKey,
        blob: escrow,
        pinned: true,
        ttlSec: (expiresAt - now).clamp(1, 259200),
        now: now);
    g.pendingInvites.add(PendingInvite(
        inviteId: inviteId,
        t: token.t,
        expiresAt: expiresAt,
        status: InviteStatus.open));
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
    return InviteHandle(
        inviteId: inviteId,
        link: token.toLink(_env.sodium),
        code: token.toCode(_env.sodium),
        token: token);
  }

  /// Bob redeems a porch:// link or pasted code (§3.5 step 3). Throws
  /// [ArgumentError] for a malformed code, [RelayGone] when already used.
  Future<JoinedInvite> redeem(String linkOrCode) async {
    final token = InviteToken.parse(_env.sodium, linkOrCode);
    if (token == null) {
      throw ArgumentError.value(
          linkOrCode, 'linkOrCode', 'not a valid Porch invite');
    }
    final state = await _load();
    final blob = buildJoinBlob(
      _env.sodium,
      token: token,
      signPk: _env.identity.sign.publicKey,
      boxPk: _env.identity.box.publicKey,
      displayName: state.profile.displayName,
      contactNote: state.profile.contactNote,
    );
    final inviteId = token.inviteId(_env.sodium);
    await _env.relay.joinInvite(inviteId: inviteId, blob: blob);
    return JoinedInvite(inviteId: inviteId, token: token);
  }

  /// Bob completes (§3.5 step 5): take the grant (deleted server-side on
  /// retrieval), verify granter signature + roster provenance, store the
  /// group. Null while the grant has not been posted yet; a grant that
  /// FAILS VERIFICATION throws — that is an attack, not a "not yet".
  Future<StoredGroup?> completeJoin(JoinedInvite joined) async {
    final Uint8List blob;
    try {
      blob = await _env.relay.takeGrant(
          inviteId: joined.inviteId,
          proof: joined.token.grantProof(_env.sodium));
    } on RelayNotFound {
      return null; // not granted yet (or expired — inviter regenerates)
    } on RelayGone {
      return null;
    }
    final grant =
        openGrantBlob(_env.sodium, myBox: _env.identity.box, blob: blob);
    if (grant == null) {
      throw StateError('grant blob failed verification — refusing to join');
    }
    final state = await _load();
    final existing = state.groupByUuid(grant.groupUuid);
    if (existing != null) return existing;
    final group = StoredGroup(
      groupUuid: grant.groupUuid,
      name: grant.groupName,
      keys: StoredEpochKey.listFromKeyring(
          GroupKeyring.fromGrant(epoch: grant.epoch, gk: grant.gk)),
      roster: grant.roster,
    );
    state.groups.add(group);
    await _env.stateStore.save(state);
    return group;
  }

  /// Alice (or any member holding the token — incl. via escrow) fulfills
  /// (§3.5 steps 4 & 6): fetch the intro, fold + announce the JOIN, post the
  /// sealed grant. Returns how many invites were granted. A join blob that
  /// cannot be opened voids the invite ("void — regenerate" surfaces it).
  Future<int> fulfillPending(String groupUuid) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    final now = _env.now();
    var granted = 0;

    for (var i = 0; i < g.pendingInvites.length; i++) {
      final invite = g.pendingInvites[i];
      if (invite.status != InviteStatus.open) continue;
      if (invite.isExpired(now)) continue;
      final token = InviteToken(invite.t);

      final blob = await _fetchJoinOrNull(token);
      if (blob == null) continue; // nobody has joined yet

      final intro = openJoinBlob(_env.sodium, token: token, blob: blob);
      if (intro == null) {
        // Garbage from someone who saw the bare inviteId: burn the invite.
        g.pendingInvites[i] = invite.markVoided();
        continue;
      }

      var current = g.pendingInvites[i] = invite.markJoined();
      if (g.roster.isMember(intro.signPk)) {
        // Already on the roster — this handshake completed via someone
        // else (e.g. an escrow ingested long after the original grant).
        // Resolve the record; re-granting would only litter the relay.
        g.pendingInvites[i] = current.markGranted();
        continue;
      }
      {
        final op = JoinOp(
          senderSignPk: _env.identity.sign.publicKey,
          seq: 0,
          issuedAt: now,
          member: RosterEntry(
            signPk: intro.signPk,
            boxPk: intro.boxPk,
            displayName: intro.displayName,
            contactNote: intro.contactNote,
            joinedAt: now,
            isAdmin: false,
          ),
        );
        _enqueueOp(state, g, op);
        g.roster = foldRoster(g.roster, [op]).roster;
      }

      final kr = g.keyring();
      final grantBlob = buildGrantBlob(
        _env.sodium,
        recipientBoxPk: intro.boxPk,
        groupUuid: g.groupUuid,
        groupName: g.name,
        epoch: kr.current.epoch,
        gk: kr.current.gk,
        roster: g.roster,
        grantedAt: now,
        granterSign: _env.identity.sign,
      );
      await _env.relay.putGrant(
          inviteId: invite.inviteId,
          proof: token.fetchProof(_env.sodium),
          blob: grantBlob);
      g.pendingInvites[i] = current.markGranted();
      granted++;
    }
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
    return granted;
  }

  /// Mark an invite void (one tap, by anyone — §3.5 step 7).
  Future<void> voidInvite(String groupUuid, String inviteId) async {
    final state = await _load();
    final g = _require(state, groupUuid);
    final i = g.pendingInvites.indexWhere((p) => p.inviteId == inviteId);
    if (i < 0) throw StateError('unknown invite $inviteId');
    g.pendingInvites[i] = g.pendingInvites[i].markVoided();
    await _env.stateStore.save(state);
  }

  /// "void — regenerate": void the old invite and mint a genuinely fresh
  /// one. The old token stays dead; nothing is reused.
  Future<InviteHandle> regenerate(String groupUuid, String inviteId,
      {int ttlHours = 72}) async {
    await voidInvite(groupUuid, inviteId);
    return mint(groupUuid, ttlHours: ttlHours);
  }

  Future<Uint8List?> _fetchJoinOrNull(InviteToken token) async {
    try {
      return await _env.relay.fetchJoin(
          inviteId: token.inviteId(_env.sodium),
          proof: token.fetchProof(_env.sodium));
    } on RelayNotFound {
      return null;
    } on RelayGone {
      return null;
    }
  }

  void _enqueueOp(PorchState state, StoredGroup g, RosterOp op) {
    final kr = g.keyring();
    final blob = sealEnvelope(
      _env.sodium,
      type: op.type,
      fields: op.fields,
      issuedAt: op.issuedAt,
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
