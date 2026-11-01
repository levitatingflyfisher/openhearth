// notification_service — LOCAL notifications, all opt-ins OFF by default
// (BUILD-SPEC §5.2 notifyPrefs, W4 acceptance).
//
// Structure IS the privacy argument here: this service is constructed from
// a LocalNotifier only — it holds no relay handle and imports no IO, so it
// has no way to send anything. Prefs live inside the encrypted state file and are
// read here to decide whether a *local* banner fires after a refresh diff.
// The server cannot learn who watches whom because the watching happens
// entirely on this side of the ciphertext.
//
// The platform notification plugin binding is a leaf adapter (W5 wires it);
// v1 host-testable code depends only on this port.
import 'dart:typed_data';

import '../domain/domain.dart';
import 'porch_state.dart';

/// Minimal local-notification port. Implementations must render on-device
/// only (flutter_local_notifications adapter is the eventual binding).
abstract interface class LocalNotifier {
  Future<void> show({required String title, required String body});
}

/// Default until a platform adapter is wired: does nothing, breaks nothing.
class NoopLocalNotifier implements LocalNotifier {
  const NoopLocalNotifier();
  @override
  Future<void> show({required String title, required String body}) async {}
}

class NotificationService {
  final LocalNotifier _notifier;
  const NotificationService(this._notifier);

  /// Compare [previous] per-group snapshots to the ones now in [state] and
  /// fire local notifications per the opt-ins. Returns how many fired.
  ///
  /// Rules (W4 acceptance):
  /// - fresh install: prefs are empty ⇒ everything is OFF ⇒ silence;
  /// - per-friend opt-in fires once per friend NEWLY available;
  /// - per-group opt-in fires ONE digest per group with new availability;
  /// - a friend already announced per-friend never double-counts into the
  ///   same refresh's group digest;
  /// - self never notifies.
  Future<int> diffAndNotify({
    required PorchState state,
    required Map<String, PresenceSnapshot> previous,
    required Uint8List myPk,
  }) async {
    var fired = 0;
    final friendAnnounced = <String>{}; // across groups, once per friend
    for (final g in state.groups) {
      final next = state.presence[g.groupUuid];
      if (next == null) continue;
      final before = <String>{
        for (final e in previous[g.groupUuid]?.entries ??
            const <PresenceEntry>[])
          b64(e.memberSignPk),
      };

      var newInGroup = 0;
      for (final e in next.entries) {
        if (bytesEqual(e.memberSignPk, myPk)) continue;
        final key = b64(e.memberSignPk);
        if (before.contains(key)) continue; // not NEWLY available
        newInGroup++;
        if (state.notifyPrefs.perFriend[key] == true &&
            !friendAnnounced.contains(key)) {
          friendAnnounced.add(key);
          newInGroup--; // consumed by the friend-level notification
          final name = _nameOf(g, e.memberSignPk);
          await _notifier.show(
            title: '$name is on the porch',
            body: e.tag.isEmpty ? 'Available now' : e.tag,
          );
          fired++;
        }
      }

      if (newInGroup > 0 && state.notifyPrefs.perGroup[g.groupUuid] == true) {
        await _notifier.show(
          title: 'Someone is on the porch in ${g.name}',
          body: newInGroup == 1
              ? 'A friend is available now'
              : '$newInGroup friends are available now',
        );
        fired++;
      }
    }
    return fired;
  }

  String _nameOf(StoredGroup g, Uint8List signPk) {
    final m = g.roster.memberOf(signPk);
    return (m == null || m.displayName.isEmpty) ? 'A friend' : m.displayName;
  }
}
