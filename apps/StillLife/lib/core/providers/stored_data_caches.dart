import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderListenable, ProviderOrFamily;

import '../../features/appraisal/presentation/controllers/appraisal_controller.dart';
import '../../features/recently_deleted/presentation/undo_providers.dart';
import 'database_provider.dart';

// What a restore must reset, and how a one-shot read keeps up with the
// database.
//
// Every restore in Still Life is a merge into the live database: the
// encrypted backup, the photo backup, Import Data and WebDAV. LAN sync
// writes into it too. A Drift watch stream follows those writes by itself.
// A one-shot read (a FutureProvider) does not, and it lives on: the tabs
// stay alive under Settings, and most providers here are not autoDispose.
// So a one-shot read of stored data calls [rereadOnDatabaseWrites], and
// what still cannot follow the database is in [storedDataResets].
//
// The guard test (test/core/providers/stored_data_caches_test.dart) fails
// when a provider is in neither place and has no ruling of its own.

/// Re-reads the calling provider after every write to the database.
///
/// Drift reports a whole transaction once, when it commits, so a restore
/// or a sync costs one re-read. The re-read is a refresh: a card keeps its
/// old value on screen until the new one is ready, so nothing flickers.
void rereadOnDatabaseWrites(Ref ref) {
  final writes = ref
      .watch(databaseProvider)
      .tableUpdates()
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(writes.cancel);
}

typedef Invalidate = void Function(ProviderOrFamily provider);
typedef Read = T Function<T>(ProviderListenable<T> provider);

/// The screens whose Undo offer lives in [screenUndoControllerProvider].
/// The guard test checks this against every key the screens use.
const undoScreens = ['categories', 'maintenance', 'policies', 'tags'];

/// One long-lived provider that a restore must reset, and how.
class StoredDataReset {
  const StoredDataReset(this.provider, this.reset);
  final ProviderOrFamily provider;
  final void Function(Invalidate invalidate, Read read) reset;
}

/// Each long-lived provider that holds stored data or a pending write and
/// does not follow the database by itself, in the order a restore resets
/// them.
///
/// The Undo offers come first. An offer made before the restore would
/// write its old rows over the merged ones: an item Undo un-deletes the
/// item and sets its old tags, a screen Undo un-deletes its row, and each
/// stamps a fresh clock, so the old state also wins the next sync.
/// Dismissing ends an offer without undoing; no Undo in Still Life has an
/// onCommit, so dismissing writes nothing (the guard test keeps it so).
final storedDataResets = <StoredDataReset>[
  StoredDataReset(
    shellUndoControllerProvider,
    (_, read) => read(shellUndoControllerProvider).dismiss(),
  ),
  StoredDataReset(screenUndoControllerProvider, (_, read) {
    // An offer on a screen that is not open was ended when it closed; this
    // read then makes an empty controller, which is disposed again.
    for (final screen in undoScreens) {
      read(screenUndoControllerProvider(screen)).dismiss();
    }
  }),
  // Holds the appraise sheet's last answer per item, read once from the
  // database. Not re-read on writes: an appraisal in flight sets this
  // state itself, and a re-read would race it.
  StoredDataReset(
    appraisalControllerProvider,
    (invalidate, _) => invalidate(appraisalControllerProvider),
  ),
];

/// Resets every cache in [storedDataResets]. Every restore calls it after
/// its merge: the restore hook, the photo backup, Import Data and WebDAV.
/// Still Life has no erase; one would call this too.
void forgetCachedData(Invalidate invalidate, Read read) {
  for (final entry in storedDataResets) {
    entry.reset(invalidate, read);
  }
}
