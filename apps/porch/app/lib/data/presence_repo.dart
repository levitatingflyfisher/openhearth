// presence_repo — the optimistic outbox-first tap path (§3.4 steps 1–4).
//
// publishAvailable/publishOff flip LOCAL state first and persist it, then
// try to drain — a dead network changes nothing about the tap experience.
// The queued event carries its ABSOLUTE expiry; delivery recomputes the TTL
// and refuses to resurrect anything that expired while queued.
//
// The local flip keeps the snapshot's existing fetchedAt: fetchedAt means
// "when relay data was last fetched", and a local tap fetched nothing —
// honesty is typed, not massaged.
import '../domain/domain.dart';
import 'env.dart';
import 'outbox.dart';
import 'porch_state.dart';

class PresenceRepo {
  final PorchEnv _env;
  const PresenceRepo(this._env);

  Future<PorchState> _load() async =>
      await _env.stateStore.load() ?? PorchState.initial();

  /// Tap Available. [groupUuids] null → every defaultBroadcast group.
  /// Never throws for network failure; the tap must always succeed locally.
  Future<void> publishAvailable({
    List<String>? groupUuids,
    String tag = '',
    required int expiresAt,
  }) async {
    final state = await _load();
    final now = _env.now();
    for (final g in _targets(state, groupUuids)) {
      final kr = g.keyring();
      final post = encodePresenceOn(
        _env.sodium,
        keyring: kr,
        senderSign: _env.identity.sign,
        tag: tag,
        now: now,
        expiresAt: expiresAt,
      );
      _enqueue(state, post, expiresAt: expiresAt, now: now);
      _flipLocal(state, g.groupUuid,
          on: PresenceEntry(
            memberSignPk: _env.identity.sign.publicKey,
            tag: tag,
            issuedAt: now,
            expiresAt: expiresAt,
          ),
          now: now);
    }
    _recordPublishMetric(state, now);
    await _env.stateStore.save(state); // the tap is durable BEFORE any I/O
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
  }

  /// Manual off (§3.4 step 4): a 60 s signed tombstone overwrites the slot.
  Future<void> publishOff({List<String>? groupUuids}) async {
    final state = await _load();
    final now = _env.now();
    for (final g in _targets(state, groupUuids)) {
      final post = encodePresenceOff(
        _env.sodium,
        keyring: g.keyring(),
        senderSign: _env.identity.sign,
        now: now,
      );
      _enqueue(state, post, expiresAt: now + presenceOffTtlSeconds, now: now);
      _flipLocal(state, g.groupUuid, on: null, now: now);
    }
    await _env.stateStore.save(state);
    await Outbox.drain(state, _env.relay, now: now);
    await _env.stateStore.save(state);
  }

  /// Flush the queue (reconnect, background flush, before a refresh).
  /// Returns how many entries remain (0 = clear). Never throws for
  /// delivery failures.
  Future<int> drainOutbox() async {
    final state = await _load();
    final remaining =
        await Outbox.drain(state, _env.relay, now: _env.now());
    await _env.stateStore.save(state);
    return remaining;
  }

  List<StoredGroup> _targets(PorchState state, List<String>? groupUuids) {
    if (groupUuids == null) {
      return [
        for (final g in state.groups)
          if (g.defaultBroadcast) g,
      ];
    }
    return [
      for (final uuid in groupUuids)
        state.groupByUuid(uuid) ??
            (throw StateError('unknown group $uuid')),
    ];
  }

  void _enqueue(PorchState state, PresencePost post,
      {required int expiresAt, required int now}) {
    Outbox.enqueue(state,
        op: OutboxOp.presence,
        payload: {
          'channelId': post.channelId,
          'slotId': post.slotId,
          'blob': b64(post.blob),
          'expiresAt': expiresAt,
        },
        now: now);
  }

  /// Upsert/remove my own entry in the group's local snapshot. Keeps the
  /// old fetchedAt (no fetch happened); a first-ever snapshot gets [now].
  void _flipLocal(PorchState state, String groupUuid,
      {required PresenceEntry? on, required int now}) {
    final old = state.presence[groupUuid];
    final myPk = _env.identity.sign.publicKey;
    state.presence[groupUuid] = PresenceSnapshot(
      entries: [
        if (old != null)
          for (final e in old.entries)
            if (!bytesEqual(e.memberSignPk, myPk)) e,
        ?on,
      ],
      fetchedAt: old?.fetchedAt ?? now,
    );
  }

  /// On-device metrics only (§1.4): stored locally, shown only to the user,
  /// asserted never to appear in any outbound payload.
  void _recordPublishMetric(PorchState state, int now) {
    final dt = DateTime.fromMillisecondsSinceEpoch(now * 1000, isUtc: true);
    final date = '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    for (final m in state.metrics) {
      if (m.date == date) {
        m.publishes++;
        m.lastAt = now;
        return;
      }
    }
    state.metrics
        .add(MetricsDay(date: date, publishes: 1, firstAt: now, lastAt: now));
  }
}
