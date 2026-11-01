// W4: notification_service — LOCAL notifications only, every opt-in OFF by
// default (BUILD-SPEC W4 acceptance). The server never learns who watches
// whom: prefs live in the encrypted state file and this service has no
// relay reference at all (structurally asserted below).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/notification_service.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/harness.dart';

class RecordingNotifier implements LocalNotifier {
  final shown = <(String, String)>[];
  @override
  Future<void> show({required String title, required String body}) async {
    shown.add((title, body));
  }
}

Uint8List _pk(int seed) => Uint8List.fromList(List.filled(32, seed));

RosterEntry _member(int seed, String name) => RosterEntry(
      signPk: _pk(seed),
      boxPk: _pk(seed + 100),
      displayName: name,
      contactNote: '',
      joinedAt: 1000 + seed,
      isAdmin: seed == 1,
    );

PresenceEntry _on(int seed, {String tag = ''}) => PresenceEntry(
      memberSignPk: _pk(seed),
      tag: tag,
      issuedAt: 2000,
      expiresAt: 9999,
    );

/// A state with one group ("Porch"), members Me(1), Sarah(2), Ravi(3).
PorchState _state({Map<String, PresenceSnapshot>? presence}) {
  final state = PorchState.initial();
  state.groups.add(StoredGroup(
    groupUuid: 'g1',
    name: 'My Porch',
    keys: [StoredEpochKey(epoch: 1, gk: _pk(9))],
    roster: Roster(members: [
      _member(1, 'Me'),
      _member(2, 'Sarah'),
      _member(3, 'Ravi'),
    ]),
  ));
  if (presence != null) state.presence.addAll(presence);
  return state;
}

void main() {
  test('fresh install: every opt-in is OFF and nothing ever fires', () async {
    final notifier = RecordingNotifier();
    final service = NotificationService(notifier);
    final state = _state(presence: {
      'g1': PresenceSnapshot(entries: [_on(2), _on(3)], fetchedAt: 5000),
    });
    expect(state.notifyPrefs.perFriend, isEmpty, reason: 'default OFF');
    expect(state.notifyPrefs.perGroup, isEmpty, reason: 'default OFF');

    final fired = await service.diffAndNotify(
        state: state, previous: const {}, myPk: _pk(1));
    expect(fired, 0);
    expect(notifier.shown, isEmpty);
  });

  test('per-friend opt-in fires once when that friend becomes available, '
      'and never re-fires for an unchanged feed', () async {
    final notifier = RecordingNotifier();
    final service = NotificationService(notifier);
    final state = _state(presence: {
      'g1': PresenceSnapshot(
          entries: [_on(2, tag: '\u{1F6B6}'), _on(3)], fetchedAt: 5000),
    });
    state.notifyPrefs.perFriend[b64(_pk(2))] = true; // watch Sarah only

    // Ravi was already on; Sarah is new.
    final previous = {
      'g1': PresenceSnapshot(entries: [_on(3)], fetchedAt: 4000),
    };
    final fired = await service.diffAndNotify(
        state: state, previous: previous, myPk: _pk(1));
    expect(fired, 1);
    expect(notifier.shown.single.$1, contains('Sarah'));

    // Same feed again → nobody is NEWLY available → silence.
    notifier.shown.clear();
    final again = await service.diffAndNotify(
        state: state,
        previous: state.presence,
        myPk: _pk(1));
    expect(again, 0);
    expect(notifier.shown, isEmpty);
  });

  test('per-group opt-in fires once per refresh for the group; my own tap '
      'never notifies me', () async {
    final notifier = RecordingNotifier();
    final service = NotificationService(notifier);
    final state = _state(presence: {
      'g1': PresenceSnapshot(
          entries: [_on(1), _on(2), _on(3)], fetchedAt: 5000),
    });
    state.notifyPrefs.perGroup['g1'] = true;

    final fired = await service.diffAndNotify(
        state: state, previous: const {}, myPk: _pk(1));
    // Two friends appeared but the group fires ONE digest; self excluded.
    expect(fired, 1);
    expect(notifier.shown.single.$1, contains('My Porch'));
    expect(notifier.shown.single.$1, isNot(contains('Me')));
  });

  test('a friend watched per-friend does not also trigger the group digest '
      'twice for the same refresh', () async {
    final notifier = RecordingNotifier();
    final service = NotificationService(notifier);
    final state = _state(presence: {
      'g1': PresenceSnapshot(entries: [_on(2)], fetchedAt: 5000),
    });
    state.notifyPrefs.perFriend[b64(_pk(2))] = true;
    state.notifyPrefs.perGroup['g1'] = true;

    final fired = await service.diffAndNotify(
        state: state, previous: const {}, myPk: _pk(1));
    expect(fired, 1, reason: 'friend-level wins; no duplicate group ping');
    expect(notifier.shown.single.$1, contains('Sarah'));
  });

  test('structural: the service has no relay access — prefs cannot reach '
      'the network from here', () {
    final src = File('lib/data/notification_service.dart').readAsStringSync();
    expect(src.contains('relay_api.dart'), isFalse);
    expect(src.contains('RelayApi'), isFalse);
    expect(src.contains('dart:io'), isFalse);
  });

  test('end-to-end: with prefs set, nothing pref-shaped appears in any '
      'plaintext the relay could ever decrypt or store', () async {
    final world = await TestWorld.create();
    final alice = await TestDevice.onboard(world, name: 'Alice', seed: 1);

    // Alice sets prefs, creates a group, publishes, refreshes.
    final g = await alice.groups.createGroup('My Porch');
    final st = await alice.state();
    st.notifyPrefs.perGroup[g.groupUuid] = true;
    st.notifyPrefs.perFriend['watched-friend-key'] = true;
    await alice.store.save(st);
    await alice.presence.publishAvailable(expiresAt: world.clock.nowSec + 3600);
    await alice.sync.refreshFeed();

    // Decrypt EVERYTHING on the relay with Alice's own keys: no envelope
    // plaintext may carry anything pref-shaped.
    final state = await alice.state();
    final group = state.groups.single;
    final kr = group.keyring();
    final chId = deriveChannelId(world.sodium, kr.current.gk);
    final blobs = <Uint8List>[
      for (final s in await world.relay.presenceGet(chId)) s.blob,
      for (final e in await world.relay.bulletinGet(chId)) e.blob,
    ];
    expect(blobs, isNotEmpty, reason: 'the publish must have landed');
    for (final blob in blobs) {
      final env = openEnvelope(world.sodium, wire: blob, keyring: kr);
      if (env == null) continue;
      final plaintext = jsonEncode(env.fields);
      expect(plaintext, isNot(contains('notifyPrefs')));
      expect(plaintext, isNot(contains('perFriend')));
      expect(plaintext, isNot(contains('perGroup')));
      expect(plaintext, isNot(contains('watched-friend-key')));
    }
  });
}
