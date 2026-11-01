// W4: the feed view-model — built ONLY from PresenceSnapshots (whose type
// carries fetchedAt by construction), deduped across groups, self split out.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/presentation/feed_model.dart';

Uint8List _pk(int seed) => Uint8List.fromList(List.filled(32, seed));

RosterEntry _member(int seed, String name, {String note = ''}) => RosterEntry(
      signPk: _pk(seed),
      boxPk: _pk(seed + 100),
      displayName: name,
      contactNote: note,
      joinedAt: 1000 + seed,
      isAdmin: seed == 1,
    );

StoredGroup _group(String uuid, String name, List<RosterEntry> members) =>
    StoredGroup(
      groupUuid: uuid,
      name: name,
      keys: [StoredEpochKey(epoch: 1, gk: _pk(9))],
      roster: Roster(members: members),
    );

PresenceEntry _on(int seed, {String tag = '', int expiresAt = 9000}) =>
    PresenceEntry(
        memberSignPk: _pk(seed), tag: tag, issuedAt: 2000, expiresAt: expiresAt);

void main() {
  const now = 5000;

  test('friends listed longest-remaining first, with names and contact notes '
      'from the roster; self becomes myStatus, never a feed row', () {
    final state = PorchState.initial();
    state.groups.add(_group('g1', 'My Porch', [
      _member(1, 'Me'),
      _member(2, 'Sarah', note: 'call my cell'),
      _member(3, 'Ravi'),
    ]));
    state.presence['g1'] = PresenceSnapshot(entries: [
      _on(1, expiresAt: 6000, tag: 'me-tag'),
      _on(2, expiresAt: 9000, tag: '\u{1F6B6}'),
      _on(3, expiresAt: 7000),
    ], fetchedAt: now - 60);

    final model = buildFeedModel(state, myPk: _pk(1), now: now);
    expect([for (final f in model.friends) f.name], ['Sarah', 'Ravi']);
    expect(model.friends[0].tag, '\u{1F6B6}');
    expect(model.friends[0].contactNote, 'call my cell');
    expect(model.friends[0].groupNames, ['My Porch']);
    expect(model.myStatus, isNotNull);
    expect(model.myStatus!.expiresAt, 6000);
    expect(model.myStatus!.tag, 'me-tag');
    expect(model.oldestFetchedAt, now - 60);
  });

  test('cross-group dedupe keeps the longest-remaining entry and lists every '
      'group the friend is visible in; expired entries drop', () {
    final state = PorchState.initial();
    state.groups.add(_group('g1', 'Porch', [_member(1, 'Me'), _member(2, 'Sarah')]));
    state.groups.add(_group('g2', 'Book club', [
      _member(1, 'Me'),
      _member(2, 'Sarah'),
      _member(4, 'Kim'),
    ]));
    state.presence['g1'] = PresenceSnapshot(
        entries: [_on(2, expiresAt: 7000)], fetchedAt: 4000);
    state.presence['g2'] = PresenceSnapshot(
        entries: [_on(2, expiresAt: 9000, tag: 'x'), _on(4, expiresAt: 4500)],
        fetchedAt: 4900);

    final model = buildFeedModel(state, myPk: _pk(1), now: now);
    // Kim expired at 4500 < now; Sarah appears once with the g2 expiry.
    expect(model.friends, hasLength(1));
    expect(model.friends.single.name, 'Sarah');
    expect(model.friends.single.expiresAt, 9000);
    expect(model.friends.single.groupNames, ['Porch', 'Book club']);
    // Honesty: the OLDEST fetch is what the staleness line must report.
    expect(model.oldestFetchedAt, 4000);
  });

  test('no snapshots at all → empty model with null oldestFetchedAt (a UI '
      'must render "never fetched", not fake freshness)', () {
    final state = PorchState.initial();
    state.groups.add(_group('g1', 'Porch', [_member(1, 'Me')]));
    final model = buildFeedModel(state, myPk: _pk(1), now: now);
    expect(model.friends, isEmpty);
    expect(model.myStatus, isNull);
    expect(model.oldestFetchedAt, isNull);
    expect(model.isStale(now), isFalse);
  });

  test('staleness is the snapshot rule: >15 min old', () {
    final state = PorchState.initial();
    state.groups.add(_group('g1', 'Porch', [_member(1, 'Me'), _member(2, 'S')]));
    state.presence['g1'] =
        PresenceSnapshot(entries: [_on(2)], fetchedAt: now - 16 * 60);
    final model = buildFeedModel(state, myPk: _pk(1), now: now);
    expect(model.isStale(now), isTrue);
    final fresh = PorchState.initial();
    fresh.groups.add(_group('g1', 'Porch', [_member(1, 'Me'), _member(2, 'S')]));
    fresh.presence['g1'] =
        PresenceSnapshot(entries: [_on(2)], fetchedAt: now - 14 * 60);
    expect(buildFeedModel(fresh, myPk: _pk(1), now: now).isStale(now), isFalse);
  });
}
