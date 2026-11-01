// FakeRelay — an in-memory RelayApi with the Go relay's EXACT semantics
// (BUILD-SPEC §4, §5.4): server-assigned monotonic seq, atomic one-time
// join, proof pinning, grant delete-after-retrieval, native TTLs on an
// injectable clock, ring-of-8 bulletins, pinned entries with their own TTL,
// mailbox depth cap, and full drain-signature verification (incl. the
// replay cache). It exists so repository and sync tests exercise honest
// server behavior with zero services — the same reason the Go side has
// memstore.
//
// Failure injection: set [offline] and every call throws RelayUnreachable;
// [callLog] records op names for ordering assertions.
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../domain/domain.dart' show b64urlNoPad, concatBytes;
import 'relay_api.dart';

// Caps mirrored from relay/internal/api/router.go — tunable there, pinned
// here so client-side tests catch cap violations before integration.
const _maxJoinBlob = 8 << 10;
const _maxGrantBlob = 16 << 10;
const _maxMailboxBlob = 8 << 10;
const _maxPresenceBlob = 1 << 10;
const _maxBulletinBlob = 8 << 10;
const _maxPresenceTtl = 14700;
const _maxPinnedTtl = 259200;
const _maxInviteHours = 72;
const _mailboxDepthCap = 200;
const _ringSize = 8;
const _pinCap = 16;
const _drainFreshness = 300;
const _replayTtl = 600;

class _Invite {
  final int expiresAt;
  bool joined = false;
  Uint8List? joinBlob;
  Uint8List? grantBlob;
  String? fetchProofPin;
  String? grantProofPin;
  _Invite(this.expiresAt);
}

class _Slot {
  final Uint8List blob;
  final int expiresAt;
  _Slot(this.blob, this.expiresAt);
}

class _Bulletin {
  final int seq;
  final Uint8List blob;
  final bool pinned;
  final int? expiresAt; // pinned only
  _Bulletin(this.seq, this.blob, this.pinned, this.expiresAt);
}

class FakeRelay implements RelayApi {
  final Sodium _sodium;

  /// The fake's clock — advance it to expire things. Unix seconds.
  int nowSec;

  /// When true every call throws [RelayUnreachable] without touching state.
  bool offline = false;

  /// Channels whose writes throw [RelayUnreachable] without touching
  /// state, for one group the relay cannot reach while others work.
  final unreachableChannels = <String>{};

  /// Op names in call order, for ordering assertions in sync tests.
  final callLog = <String>[];

  /// The writer id each bulletin write named, per channel, in order (null:
  /// it named none).
  final bulletinWriters = <String, List<String?>>{};

  /// Whether the relay counts [channelId] as confirmed: two different ids
  /// have written there, presence slots or bulletin writer ids
  /// (relay/internal/store, ChannelFreshTTL).
  bool channelConfirmed(String channelId) =>
      (_slotsSeen[channelId]?.length ?? 0) >= 2;

  /// Every slot that has written to a channel, by presence or by a named
  /// bulletin write.
  final _slotsSeen = <String, Set<String>>{};

  final _invites = <String, _Invite>{};
  final _mailboxes = <String, List<Uint8List>>{};
  final _presence = <String, Map<String, _Slot>>{};
  final _bulletins = <String, List<_Bulletin>>{};
  final _seq = <String, int>{};
  final _replay = <String, int>{}; // sigHash(b64url) → expiresAt

  FakeRelay(this._sodium, {required this.nowSec});

  void _enter(String op) {
    callLog.add(op);
    if (offline) throw const RelayUnreachable('fake relay offline');
  }

  // --- invites ---

  @override
  Future<int> createInvite(
      {required String inviteId, required int ttlHours}) async {
    _enter('createInvite');
    if (ttlHours < 1 || ttlHours > _maxInviteHours) {
      throw const RelayBadRequest();
    }
    final existing = _liveInvite(inviteId);
    if (existing != null) throw const RelayConflict();
    final expiresAt = nowSec + ttlHours * 3600;
    _invites[inviteId] = _Invite(expiresAt);
    return expiresAt;
  }

  @override
  Future<void> joinInvite(
      {required String inviteId, required Uint8List blob}) async {
    _enter('joinInvite');
    if (blob.length > _maxJoinBlob) throw const RelayTooLarge();
    final inv = _liveInvite(inviteId);
    if (inv == null) throw const RelayNotFound();
    if (inv.joined) throw const RelayGone(); // atomic open→joined (SET NX)
    inv.joined = true;
    inv.joinBlob = Uint8List.fromList(blob);
  }

  @override
  Future<Uint8List> fetchJoin(
      {required String inviteId, required String proof}) async {
    _enter('fetchJoin');
    final inv = _liveInvite(inviteId);
    if (inv == null || inv.joinBlob == null) throw const RelayNotFound();
    // First-use proof pinning (see relay HONEST-STATUS design decision):
    // the server never held t, so it pins the first proof presented.
    inv.fetchProofPin ??= proof;
    if (inv.fetchProofPin != proof) throw const RelayNotFound();
    return Uint8List.fromList(inv.joinBlob!);
  }

  @override
  Future<void> putGrant(
      {required String inviteId,
      required String proof,
      required Uint8List blob}) async {
    _enter('putGrant');
    if (blob.length > _maxGrantBlob) throw const RelayTooLarge();
    final inv = _liveInvite(inviteId);
    if (inv == null) throw const RelayNotFound();
    inv.fetchProofPin ??= proof;
    if (inv.fetchProofPin != proof) throw const RelayNotFound();
    inv.grantBlob = Uint8List.fromList(blob);
  }

  @override
  Future<Uint8List> takeGrant(
      {required String inviteId, required String proof}) async {
    _enter('takeGrant');
    final inv = _liveInvite(inviteId);
    if (inv == null || inv.grantBlob == null) throw const RelayNotFound();
    inv.grantProofPin ??= proof;
    if (inv.grantProofPin != proof) throw const RelayNotFound();
    final blob = inv.grantBlob!;
    inv.grantBlob = null; // deleted after retrieval (§4 row 5)
    return blob;
  }

  _Invite? _liveInvite(String id) {
    final inv = _invites[id];
    if (inv == null) return null;
    if (nowSec > inv.expiresAt) {
      _invites.remove(id); // native TTL death — expired == unknown (404)
      return null;
    }
    return inv;
  }

  // --- mailbox ---

  @override
  Future<void> mailboxPost(
      {required String mailboxId, required Uint8List blob}) async {
    _enter('mailboxPost');
    if (blob.length > _maxMailboxBlob) throw const RelayTooLarge();
    final box = _mailboxes.putIfAbsent(mailboxId, () => []);
    if (box.length >= _mailboxDepthCap) throw const RelayRateLimited();
    box.add(Uint8List.fromList(blob));
  }

  @override
  Future<List<Uint8List>> mailboxDrain(
      {required String mailboxId, required DrainAuth auth}) async {
    _enter('mailboxDrain');
    _verifyDrain(mailboxId, auth);
    final box = _mailboxes.remove(mailboxId) ?? [];
    return box; // atomic: returned == deleted
  }

  /// Full server-side verification (relay sigauth.go): key shape, mailbox
  /// binding, ±300 s freshness, Ed25519 signature, replay cache on
  /// hash(sig).
  void _verifyDrain(String mailboxId, DrainAuth auth) {
    if (auth.pubkey.length != 32 || auth.sig.length != 64) {
      throw const RelayUnauthorized();
    }
    final derived = b64urlNoPad(_sodium.crypto.genericHash(
      message: concatBytes(['porch/mbox/v1'.codeUnits, auth.pubkey]),
      outLen: 32,
    ));
    if (derived != mailboxId) throw const RelayUnauthorized();
    if ((nowSec - auth.ts).abs() > _drainFreshness) {
      throw const RelayUnauthorized();
    }
    final msg = 'porch-drain|$mailboxId|${auth.ts}';
    final ok = _sodium.crypto.sign.verifyDetached(
      message: Uint8List.fromList(msg.codeUnits),
      signature: auth.sig,
      publicKey: auth.pubkey,
    );
    if (!ok) throw const RelayUnauthorized();
    _replay.removeWhere((_, exp) => nowSec > exp);
    final sigHash =
        b64urlNoPad(_sodium.crypto.genericHash(message: auth.sig, outLen: 32));
    if (_replay.containsKey(sigHash)) throw const RelayUnauthorized();
    _replay[sigHash] = nowSec + _replayTtl;
  }

  // --- channel plane ---

  @override
  Future<void> presencePost(
      {required String channelId,
      required String slotId,
      required Uint8List blob,
      required int ttlSec}) async {
    _enter('presencePost');
    if (unreachableChannels.contains(channelId)) {
      throw const RelayUnreachable('fake relay: channel unreachable');
    }
    if (blob.length > _maxPresenceBlob) throw const RelayTooLarge();
    if (ttlSec < 1 || ttlSec > _maxPresenceTtl) throw const RelayBadRequest();
    _slotsSeen.putIfAbsent(channelId, () => {}).add(slotId);
    _presence.putIfAbsent(channelId, () => {})[slotId] =
        _Slot(Uint8List.fromList(blob), nowSec + ttlSec);
  }

  @override
  Future<List<PresenceSlot>> presenceGet(String channelId) async {
    _enter('presenceGet');
    final slots = _presence[channelId];
    if (slots == null) return [];
    slots.removeWhere((_, s) => nowSec >= s.expiresAt); // native TTL
    final out = [
      for (final e in slots.entries)
        PresenceSlot(
            slotId: e.key, blob: e.value.blob, expiresAt: e.value.expiresAt),
    ]..sort((a, b) => a.slotId.compareTo(b.slotId));
    return out;
  }

  @override
  Future<int> bulletinPost(
      {required String channelId,
      required Uint8List blob,
      bool pinned = false,
      int ttlSec = 0,
      String? slotId}) async {
    _enter('bulletinPost');
    if (unreachableChannels.contains(channelId)) {
      throw const RelayUnreachable('fake relay: channel unreachable');
    }
    bulletinWriters.putIfAbsent(channelId, () => []).add(slotId);
    if (slotId != null) _slotsSeen.putIfAbsent(channelId, () => {}).add(slotId);
    if (blob.length > _maxBulletinBlob) throw const RelayTooLarge();
    if (pinned && (ttlSec < 1 || ttlSec > _maxPinnedTtl)) {
      throw const RelayBadRequest();
    }
    if (!pinned && ttlSec != 0) throw const RelayBadRequest();
    final list = _bulletins.putIfAbsent(channelId, () => []);
    _expirePins(list);
    if (pinned && list.where((e) => e.pinned).length >= _pinCap) {
      throw const RelayRateLimited();
    }
    final seq = (_seq[channelId] ?? 0) + 1;
    _seq[channelId] = seq;
    list.add(_Bulletin(seq, Uint8List.fromList(blob), pinned,
        pinned ? nowSec + ttlSec : null));
    // Ring of 8: evict oldest UNPINNED only.
    while (list.where((e) => !e.pinned).length > _ringSize) {
      list.remove(list.firstWhere((e) => !e.pinned));
    }
    return seq;
  }

  @override
  Future<List<BulletinEntry>> bulletinGet(String channelId,
      {int afterSeq = 0}) async {
    _enter('bulletinGet');
    final list = _bulletins[channelId];
    if (list == null) return [];
    _expirePins(list);
    return [
      for (final e in list)
        if (e.seq > afterSeq)
          BulletinEntry(
              seq: e.seq, blob: e.blob, pinned: e.pinned, expiresAt: e.expiresAt),
    ]..sort((a, b) => a.seq - b.seq);
  }

  void _expirePins(List<_Bulletin> list) =>
      list.removeWhere((e) => e.pinned && nowSec >= e.expiresAt!);

  @override
  Future<bool> healthz() async {
    _enter('healthz');
    return true;
  }

  /// Test convenience: number of undrained blobs in a mailbox.
  int mailboxDepth(String mailboxId) => _mailboxes[mailboxId]?.length ?? 0;

  /// Simulate TOTAL relay data loss (§5.4 "total loss degrades
  /// gracefully"): every store — invites, mailboxes, presence, bulletins,
  /// seq counters, replay cache — vanishes. Clients must recover via the
  /// rekey-request self-heal.
  void wipeAll() {
    _invites.clear();
    _mailboxes.clear();
    _presence.clear();
    _bulletins.clear();
    _seq.clear();
    _replay.clear();
  }

  /// Test convenience: true iff any slot is live on [channelId].
  bool hasLivePresence(String channelId) {
    final slots = _presence[channelId];
    if (slots == null) return false;
    return slots.values.any((s) => nowSec < s.expiresAt);
  }
}
