// Destructive settings actions. Kept out of the widget so the erase path is a
// single, testable unit: wipe what is stored, then forget every copy of it
// held in memory and end any write still waiting, so nothing from before
// shows on screen or comes back.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/sync/presentation/sync_screen.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

/// Every provider that lives as long as the app and holds a copy of stored
/// data. Erase and restore change what is stored, so both reset this whole
/// list through [_forgetCachedData]. Screen providers are autoDispose and
/// Drift watch streams follow the database, so they need nothing.
/// `stored_data_caches_guard_test.dart` finds every long-lived provider in
/// lib/ and fails until a new one is either added here or ruled to hold no
/// stored data.
final List<ProviderOrFamily> storedDataCaches = [
  aiConfigProvider,
];

/// What "Erase all data" did.
enum EraseOutcome {
  /// A verified safety copy is in Previous backups; restoring it undoes the
  /// erase.
  erasedWithSafetyCopy,

  /// No recovery words, so no copy could be sealed; the person agreed in a
  /// dialog that said there is no way back.
  erasedNoCopy,

  /// The safety copy failed, so nothing was erased.
  keptBecauseSnapshotFailed,
}

/// The erase, behind sanctuary_backup_ui's pre-wipe snapshot: wipe only once
/// a verified copy of the current data is in the vault, never after the copy
/// failed. With no recovery words there is no copy to take, and the wipe goes
/// ahead only if the person was told so ([promisedCopy] false): someone who
/// agreed to an erase with a safety copy did not agree to one without.
/// (A small function over the two calls so the rule is testable on its
/// own.)
Future<EraseOutcome> eraseAfterSnapshot({
  required Future<PreWipeSnapshot> Function() snapshot,
  required Future<void> Function() wipe,
  required bool promisedCopy,
}) async {
  final snap = await snapshot();
  switch (snap.outcome) {
    case PreWipeOutcome.taken:
      await wipe();
      return EraseOutcome.erasedWithSafetyCopy;
    case PreWipeOutcome.noKey:
      if (promisedCopy) return EraseOutcome.keptBecauseSnapshotFailed;
      await wipe();
      return EraseOutcome.erasedNoCopy;
    case PreWipeOutcome.failed:
      return EraseOutcome.keptBecauseSnapshotFailed;
  }
}

/// Erase all data. It takes the household's records, the unsaved recipe
/// drafts, the AI settings with the AI key and the stove phrase, the
/// household sync code and the suggestion card's settings. It keeps what the
/// button and dialog name: the theme, the built-in food database, the
/// offline barcode database and the downloaded AI model. The last three hold
/// nothing of the household's. (The sync clock's device id and counter stay
/// too; they hold no household content.)
Future<void> eraseAllData(WidgetRef ref) async {
  // Stop serving first: a peer must not sync into the data mid-wipe, and the
  // server must not outlive the household code it is keyed by.
  if (ref.exists(lanSyncServerProvider)) {
    await ref.read(lanSyncServerProvider).stop();
  }
  await ref.read(appDatabaseProvider).eraseUserData();
  // Unsaved recipe drafts are the household's words too.
  await ref.read(recipeDraftStoreProvider).clearAll();
  await ref.read(aiConfigRepositoryProvider).erase();
  await ref.read(syncSecretStoreProvider).delete();
  await ref.read(settingsRepositoryProvider).resetSuggestions();

  await _forgetCachedData(ref.invalidate, ref.read(undoControllerProvider));
}

/// The `Ref`-typed hook `SanctuaryBackupConfig.onAfterRestore` runs after a
/// destructive encrypted-backup restore (SANCTUARY-BRIEF §4.W2). It forgets
/// the same cached data as [eraseAllData], through the same
/// [_forgetCachedData].
///
/// A restore replaces the household's records and nothing else: the AI
/// settings and the sync code are not in a backup, so they stay. The recipe
/// drafts are not in a backup either, but they go: a draft edit of a recipe
/// the restore replaced would be saved over the restored one.
Future<void> afterBackupRestore(Ref ref) async {
  await ref.read(recipeDraftStoreProvider).clearAll();
  await _forgetCachedData(ref.invalidate, ref.read(undoControllerProvider));
}

/// Erase and restore both swap the data under the app, so both forget every
/// cached copy of it, through this one function so the two cannot drift
/// apart. Each provider in [storedDataCaches] reloads. The app-wide Undo is
/// cancelled, never undone and never committed: it holds a row from before
/// (a diary line, grocery item, plan cell, recipe or custom food), and
/// tapping Undo would write that row back into the erased or restored data.
/// cancel() runs neither onUndo nor onCommit, so an offer's onCommit, which
/// was written against the data from before, cannot remove a restored row
/// with the same id. The reset no longer depends on Peckish Undos having no
/// onCommit; `undo_no_commit_test.dart` still keeps ordinary dismissals
/// free of one.
/// [invalidate] is `ref.invalidate` from either kind of ref (a `WidgetRef`
/// for erase, a `Ref` for restore); Riverpod gives them no common supertype.
Future<void> _forgetCachedData(
  void Function(ProviderOrFamily) invalidate,
  OhUndoController undo,
) async {
  storedDataCaches.forEach(invalidate);
  undo.cancel();
}
