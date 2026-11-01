import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/features/export/presentation/export_screen.dart';
import 'package:sundial/features/sessions/presentation/session_undo.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';
import 'package:sundial/features/timer/presentation/unsaved_session_panel.dart';

/// One long-lived provider that holds stored data, or a write waiting to
/// happen, and how a restore resets it.
typedef StoredDataReset = ({
  ProviderOrFamily provider,
  void Function(Ref ref) reset,
});

/// Every long-lived provider that keeps stored data in memory or holds a
/// pending write. A restore replaces the database behind them, so the
/// restore hook resets this whole list through [forgetCachedData]. Sundial
/// has no erase; if one comes, it calls the same function.
/// `stored_data_caches_test.dart` fails if a long-lived provider in lib/ is
/// in neither list here.
///
/// The Drift watch streams (profiles, sessions, badges, prefs) are not here:
/// they follow the database by themselves, and every generated provider in
/// Sundial but the timer is autoDispose.
///
/// The Undo offers come first, so neither can fire into the restored record
/// while the rest is reset.
final List<StoredDataReset> storedDataResets = [
  // Both offers are cancelled: neither its Undo nor an onCommit runs, so the
  // reset does not depend on what an offer carries.
  // "Deleted 1h on Wed, Apr 1": its Undo writes the old session back.
  (
    provider: sessionUndoControllerProvider,
    reset: (ref) => ref.read(sessionUndoControllerProvider).cancel(),
  ),
  // "Discarded ...": its Undo puts the old draft back on the timer.
  (
    provider: timerUndoControllerProvider,
    reset: (ref) => ref.read(timerUndoControllerProvider).cancel(),
  ),
  // A running or paused timer, or an unsaved draft, with the profile id it
  // will save under, kept in memory and in its stored keys.
  (
    provider: timerProvider,
    reset: (ref) =>
        unawaited(ref.read(timerProvider.notifier).forget()),
  ),
  // The selected profile id; the backup may not hold that profile.
  // Everyone always exists. A plain invalidate would reload the old id from
  // its stored key.
  (
    provider: activeProfileIdProvider,
    reset: (ref) =>
        ref.read(activeProfileIdProvider.notifier).select(kEveryoneProfileId),
  ),
  // Badges just earned, waiting for their confetti.
  (
    provider: newlyEarnedBadgesProvider,
    reset: (ref) => ref.invalidate(newlyEarnedBadgesProvider),
  ),
];

/// Long-lived providers that hold no stored data, so nothing to reset.
final List<ProviderOrFamily> keepAliveWithoutStoredData = [
  // The device's key-value store itself. The timer's keys in it are cleared
  // by the timer's reset and the selected profile by its own; the Flow
  // screen's "rich offer dismissed" flag is a device choice, kept on purpose.
  sharedPreferencesProvider,
  // Whether this launch came from the home-screen widget.
  widgetLaunchOverrideProvider,
  widgetLaunchLifecycleObserverProvider,
  // Whether this platform can save a file to the device.
  saveToDeviceSupportedProvider,
];

/// Resets every entry in [storedDataResets], in order.
void forgetCachedData(Ref ref) {
  for (final entry in storedDataResets) {
    entry.reset(ref);
  }
}
