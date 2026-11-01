import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../app/undo_host.dart';
import '../../features/export/raw_export_controller.dart';
import '../../features/tracking/presentation/controllers/timer_controller.dart';

/// One long-lived provider that holds stored data, or a write waiting to
/// happen, and how a restore resets it.
typedef StoredDataReset = ({
  ProviderOrFamily provider,
  void Function(Ref ref) reset,
});

/// Every long-lived provider that keeps stored data in memory or holds a
/// pending write. A restore replaces the database behind them, so the
/// restore hook resets this whole list through [forgetCachedData]. Lullaby
/// has no erase; if one comes, it calls the same function.
/// `stored_data_caches_test.dart` fails if a long-lived provider in lib/ is
/// neither here nor ruled to hold no stored data.
///
/// The Drift watch streams (babies, logs, the timeline, the latest
/// measurement) are not here: they follow the database by themselves.
///
/// The Undo comes first, so it cannot fire into the restored record while
/// the rest is reset.
final List<StoredDataReset> storedDataResets = [
  // "Feed deleted" and the like: its Undo would put a row from the old
  // record into the restored one. Cancelled: neither its Undo nor its
  // onCommit runs, so the reset does not depend on what an offer carries.
  (
    provider: undoControllerProvider,
    reset: (ref) => ref.read(undoControllerProvider).cancel(),
  ),
  // The running feed and sleep timers, with the log ids they will stop.
  // Rebuilt from the restored open sessions.
  (
    provider: activeTimersProvider,
    reset: (ref) => ref.invalidate(activeTimersProvider),
  ),
  // The last CSV export, the whole record of one baby. The export
  // invalidates it before each use; a restore drops the old copy too.
  (
    provider: rawExportProvider,
    reset: (ref) => ref.invalidate(rawExportProvider),
  ),
];

/// Resets every entry in [storedDataResets], in order.
void forgetCachedData(Ref ref) {
  for (final entry in storedDataResets) {
    entry.reset(ref);
  }
}
