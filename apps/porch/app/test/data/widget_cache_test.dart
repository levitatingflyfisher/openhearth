// W3-data: widget_cache — the §5.3 contract JSON builder and the ports.
// The home_widget-backed writer is W5; the app must be complete with the
// no-op mirror.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/widget_cache.dart';
import 'package:porch_app/domain/domain.dart';

void main() {
  Uint8List pk(int seed) => Uint8List.fromList(List.filled(32, seed));

  PresenceEntry entry(int seed, String tag, {required int expiresAt}) =>
      PresenceEntry(
          memberSignPk: pk(seed),
          tag: tag,
          issuedAt: expiresAt - 3600,
          expiresAt: expiresAt);

  StoredGroup groupWith(String uuid, List<RosterEntry> members) => StoredGroup(
        groupUuid: uuid,
        name: uuid,
        keys: [StoredEpochKey(epoch: 1, gk: Uint8List(32))],
        roster: Roster(members: members),
      );

  RosterEntry member(int seed, String name) => RosterEntry(
      signPk: pk(seed),
      boxPk: pk(seed),
      displayName: name,
      contactNote: '',
      joinedAt: 0,
      isAdmin: false);

  test('builder: excludes self, dedupes across groups, caps top3, exact '
      '§5.3 JSON shape', () {
    final state = PorchState.initial();
    state.groups.add(groupWith('g1', [
      member(1, 'Me'),
      member(2, 'Sarah'),
      member(3, 'Tom'),
      member(4, 'Ana'),
      member(5, 'Ravi'),
    ]));
    state.groups.add(groupWith('g2', [member(1, 'Me'), member(2, 'Sarah')]));
    state.presence['g1'] = PresenceSnapshot(entries: [
      entry(1, '🏠', expiresAt: 5000), // me — excluded
      entry(2, '🚶', expiresAt: 4000),
      entry(3, '💻', expiresAt: 6000),
      entry(4, '📖', expiresAt: 3000),
      entry(5, '🚗', expiresAt: 2000),
    ], fetchedAt: 1000);
    state.presence['g2'] = PresenceSnapshot(
        entries: [entry(2, '🚶', expiresAt: 4500)], fetchedAt: 900);

    final snap = buildWidgetCacheSnapshot(state,
        myPk: pk(1), fallbackFetchedAt: 1234);
    expect(snap.availableCount, 4, reason: 'Sarah counted once, me excluded');
    expect([for (final f in snap.top3) f.name], ['Tom', 'Sarah', 'Ana'],
        reason: 'longest-remaining first; Sarah deduped to her max expiry');
    expect(snap.fetchedAt, 900, reason: 'oldest fetch wins — honest staleness');

    expect(snap.toJson(), {
      'schema': 1,
      'availableCount': 4,
      'top3': [
        {'name': 'Tom', 'tag': '💻', 'expiresAt': 6000},
        {'name': 'Sarah', 'tag': '🚶', 'expiresAt': 4500},
        {'name': 'Ana', 'tag': '📖', 'expiresAt': 3000},
      ],
      'fetchedAt': 900,
    });
  });

  test('empty state: zero count, empty top3, fallback fetchedAt', () {
    final snap = buildWidgetCacheSnapshot(PorchState.initial(),
        myPk: pk(1), fallbackFetchedAt: 777);
    expect(snap.availableCount, 0);
    expect(snap.top3, isEmpty);
    expect(snap.fetchedAt, 777);
  });

  test('an unknown roster name falls back without leaking key material', () {
    final state = PorchState.initial();
    state.groups.add(groupWith('g1', [member(1, 'Me')]));
    state.presence['g1'] = PresenceSnapshot(
        entries: [entry(9, '🚶', expiresAt: 4000)], fetchedAt: 100);
    final snap = buildWidgetCacheSnapshot(state,
        myPk: pk(1), fallbackFetchedAt: 0);
    expect(snap.top3.single.name, 'Friend');
  });

  test('NoopWidgetCacheMirror accepts writes and does nothing', () async {
    const mirror = NoopWidgetCacheMirror();
    await mirror.write(buildWidgetCacheSnapshot(PorchState.initial(),
        myPk: pk(1), fallbackFetchedAt: 0));
  });
}
