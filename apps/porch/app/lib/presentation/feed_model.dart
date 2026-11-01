// The feed view-model (§3.4 step 6): what the home screen renders.
//
// Built exclusively from PresenceSnapshots — the type that cannot exist
// without fetchedAt — so no rendering path can hold presence without
// knowing its age. Mirrors the widget-cache rules (§5.3): self excluded
// from the friend list, cross-group dedupe keeps the longest-remaining
// entry, and the reported fetch time is the OLDEST among the groups shown
// (the staleness line must never understate).
import 'dart:typed_data';

import '../data/porch_state.dart';
import '../domain/domain.dart';

/// One available friend, aggregated across groups.
class FeedFriend {
  final String signPkB64;
  final String name;
  final String tag;
  final int expiresAt;
  final String contactNote;
  final List<String> groupNames;
  const FeedFriend({
    required this.signPkB64,
    required this.name,
    required this.tag,
    required this.expiresAt,
    required this.contactNote,
    required this.groupNames,
  });
}

/// My own porch light, if on anywhere.
class MyStatus {
  final String tag;
  final int expiresAt;
  const MyStatus({required this.tag, required this.expiresAt});
}

class FeedModel {
  /// Available friends, longest-remaining first.
  final List<FeedFriend> friends;

  /// My own status (max expiry across groups), or null when off.
  final MyStatus? myStatus;

  /// Oldest fetchedAt among groups with a snapshot; null = never fetched.
  final int? oldestFetchedAt;

  const FeedModel({
    required this.friends,
    required this.myStatus,
    required this.oldestFetchedAt,
  });

  /// The §1.4 rule, applied to the oldest data on screen.
  bool isStale(int nowSec) {
    final t = oldestFetchedAt;
    return t != null && nowSec - t > snapshotStaleSeconds;
  }
}

FeedModel buildFeedModel(
  PorchState state, {
  required Uint8List myPk,
  required int now,
}) {
  final byFriend = <String, FeedFriend>{};
  MyStatus? mine;
  int? oldest;

  for (final g in state.groups) {
    final snap = state.presence[g.groupUuid];
    if (snap == null) continue;
    oldest = (oldest == null || snap.fetchedAt < oldest) ? snap.fetchedAt : oldest;
    for (final e in snap.entries) {
      if (e.expiresAt <= now) continue; // over — never render a dead light
      if (bytesEqual(e.memberSignPk, myPk)) {
        if (mine == null || e.expiresAt > mine.expiresAt) {
          mine = MyStatus(tag: e.tag, expiresAt: e.expiresAt);
        }
        continue;
      }
      final key = b64(e.memberSignPk);
      final member = g.roster.memberOf(e.memberSignPk);
      final seen = byFriend[key];
      if (seen == null) {
        byFriend[key] = FeedFriend(
          signPkB64: key,
          name: (member == null || member.displayName.isEmpty)
              ? 'Friend'
              : member.displayName,
          tag: e.tag,
          expiresAt: e.expiresAt,
          contactNote: member?.contactNote ?? '',
          groupNames: [g.name],
        );
      } else {
        final longer = e.expiresAt > seen.expiresAt;
        byFriend[key] = FeedFriend(
          signPkB64: key,
          name: seen.name,
          tag: longer ? e.tag : seen.tag,
          expiresAt: longer ? e.expiresAt : seen.expiresAt,
          contactNote: seen.contactNote.isNotEmpty
              ? seen.contactNote
              : (member?.contactNote ?? ''),
          groupNames: [...seen.groupNames, g.name],
        );
      }
    }
  }

  final friends = byFriend.values.toList()
    ..sort((a, b) {
      final d = b.expiresAt - a.expiresAt;
      return d != 0 ? d : a.name.compareTo(b.name);
    });
  return FeedModel(friends: friends, myStatus: mine, oldestFetchedAt: oldest);
}
