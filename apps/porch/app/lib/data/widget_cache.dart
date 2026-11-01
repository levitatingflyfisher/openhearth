// widget_cache — the §5.3 widget cache contract and its ports.
//
// The widget is a progressive enhancement: [WidgetCacheMirror] is the port,
// [NoopWidgetCacheMirror] the only W3 implementation — deleting the widget
// touches nothing else. The home_widget-backed writer (Android shared
// container) is W5. The builder here produces EXACTLY the contract JSON:
//
//   { "schema": 1, "availableCount": N,
//     "top3": [{ "name", "tag", "expiresAt" }], "fetchedAt": T }
//
// fetchedAt is the OLDEST fetch among the groups shown — the widget's
// staleness line must never understate how old its data is.
import 'dart:typed_data';

import '../domain/domain.dart' show b64, bytesEqual;
import 'porch_state.dart';

class WidgetFriend {
  final String name;
  final String tag;
  final int expiresAt;
  const WidgetFriend(
      {required this.name, required this.tag, required this.expiresAt});

  Map<String, Object?> toJson() =>
      {'name': name, 'tag': tag, 'expiresAt': expiresAt};
}

class WidgetCacheSnapshot {
  static const schema = 1;
  final int availableCount;
  final List<WidgetFriend> top3;
  final int fetchedAt;
  const WidgetCacheSnapshot(
      {required this.availableCount,
      required this.top3,
      required this.fetchedAt});

  Map<String, Object?> toJson() => {
        'schema': schema,
        'availableCount': availableCount,
        'top3': [for (final f in top3) f.toJson()],
        'fetchedAt': fetchedAt,
      };
}

abstract interface class WidgetCacheMirror {
  Future<void> write(WidgetCacheSnapshot snapshot);
}

/// The only v1-shipped mirror until W5: does nothing, breaks nothing.
class NoopWidgetCacheMirror implements WidgetCacheMirror {
  const NoopWidgetCacheMirror();
  @override
  Future<void> write(WidgetCacheSnapshot snapshot) async {}
}

/// Distill the state into the §5.3 snapshot: friends only (self excluded),
/// deduped across groups keeping the longest-remaining availability,
/// longest-remaining first. Display names come from rosters; an unknown or
/// empty name renders as "Friend" — never key material.
WidgetCacheSnapshot buildWidgetCacheSnapshot(
  PorchState state, {
  required Uint8List myPk,
  required int fallbackFetchedAt,
}) {
  final best = <String, WidgetFriend>{};
  int? oldestFetch;
  for (final g in state.groups) {
    final snap = state.presence[g.groupUuid];
    if (snap == null) continue;
    oldestFetch = oldestFetch == null
        ? snap.fetchedAt
        : (snap.fetchedAt < oldestFetch ? snap.fetchedAt : oldestFetch);
    for (final e in snap.entries) {
      if (bytesEqual(e.memberSignPk, myPk)) continue;
      final key = b64(e.memberSignPk);
      final seen = best[key];
      if (seen != null && seen.expiresAt >= e.expiresAt) continue;
      final member = g.roster.memberOf(e.memberSignPk);
      final name = (member == null || member.displayName.isEmpty)
          ? 'Friend'
          : member.displayName;
      best[key] = WidgetFriend(name: name, tag: e.tag, expiresAt: e.expiresAt);
    }
  }
  final ranked = best.values.toList()
    ..sort((a, b) {
      final d = b.expiresAt - a.expiresAt;
      return d != 0 ? d : a.name.compareTo(b.name);
    });
  return WidgetCacheSnapshot(
    availableCount: ranked.length,
    top3: ranked.take(3).toList(),
    fetchedAt: oldestFetch ?? fallbackFetchedAt,
  );
}
