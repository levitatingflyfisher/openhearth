import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:openhearth_design/openhearth_design.dart';

import '../features/home/home_screen.dart';
import '../features/matchup/matchup_notifier.dart';
import '../features/name_detail/name_detail_screen.dart';
import '../features/results/couple_results_screen.dart';
import '../features/results/solo_results_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shortlist/shortlist_screen.dart';

/// Every provider that lives as long as the app and keeps a copy of stored
/// data. None of them watches a Drift stream: each reads once and keeps
/// what it read, so a restore or an erase must invalidate each one, or the
/// old sessions and rankings stay on screen.
///
/// test/app/stored_data_caches_test.dart scans lib/ and fails when a
/// provider that is not autoDispose is in neither this list nor its table
/// of providers that hold no stored data.
final List<ProviderOrFamily> storedDataCaches = [
  allSessionsProvider,
  clearedSessionsProvider,
  shortlistEntriesProvider,
  // The session-keyed families. A family invalidates every session's copy.
  soloResultsProvider,
  methodologyProvider,
  coupleResultsProvider,
  nameDetailProvider,
  matchupProvider,
];

/// Reloads every cache in [storedDataCaches] from the database.
void refreshStoredDataCaches(void Function(ProviderOrFamily) invalidate) {
  for (final cache in storedDataCaches) {
    invalidate(cache);
  }
}

/// The one reset for a restore and for an erase (Clear all sessions and
/// Delete forever): ends a pending Clear Undo, then reloads every cache.
///
/// The Undo goes first, so it cannot un-clear session ids in data that was
/// replaced or deleted. It is cancelled, so neither its Undo nor an `onCommit`
/// runs, whatever the offer carries.
void forgetCachedData(
  void Function(ProviderOrFamily) invalidate, {
  OhUndoController? undo,
}) {
  undo?.cancel();
  refreshStoredDataCaches(invalidate);
}

/// Runs after a restore has replaced the data (the backup config's
/// `onAfterRestore`). The Clear Undo lives only while Settings is open, and
/// Settings is where the restore runs; when it is not open there is no
/// offer to end, and reading it would only make a new one.
void afterLiltRestore(Ref ref) {
  forgetCachedData(
    ref.invalidate,
    undo: ref.exists(clearSessionsUndoProvider)
        ? ref.read(clearSessionsUndoProvider)
        : null,
  );
}
