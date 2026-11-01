import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:furrow/core/providers/core_providers.dart';

/// One long-lived provider that holds stored data, or a write waiting to
/// happen, and how a restore resets it.
typedef StoredDataReset = ({
  ProviderOrFamily provider,
  void Function(Ref ref) reset,
});

/// Every long-lived provider that keeps stored data in memory or holds a
/// pending write. A restore replaces the database behind them, so the
/// restore hook resets this whole list through [forgetCachedData]. Furrow
/// has no erase (only a per-habit "Delete forever"); if one comes, it calls
/// the same function. `stored_data_caches_test.dart` fails if a long-lived
/// provider in lib/ is in neither list here.
///
/// The Drift watch streams (habits, marks, awards, prefs) are not here: they
/// follow the database by themselves, and every generated provider in
/// Furrow is autoDispose.
///
/// The Undo offer comes first, so it cannot fire into the restored field
/// while the rest is reset.
final List<StoredDataReset> storedDataResets = [
  // "Removed Walk": its Undo clears deletedAt on that habit id, which would
  // bring back a habit the backup holds as removed. Cancel runs neither the
  // Undo nor an onCommit, so the reset does not depend on what an offer carries.
  (
    provider: habitUndoProvider,
    reset: (ref) => ref.read(habitUndoProvider).cancel(),
  ),
  // Awards just earned, waiting for their confetti.
  (
    provider: newlyEarnedAwardsProvider,
    reset: (ref) => ref.invalidate(newlyEarnedAwardsProvider),
  ),
];

/// Long-lived providers that hold no stored data, so nothing to reset.
final List<ProviderOrFamily> keepAliveWithoutStoredData = [
  // The device's key-value store itself. Furrow keeps its own data in the
  // database; the backup package's keys in here are the package's to manage.
  sharedPreferencesProvider,
];

/// Resets every entry in [storedDataResets], in order.
void forgetCachedData(Ref ref) {
  for (final entry in storedDataResets) {
    entry.reset(ref);
  }
}
