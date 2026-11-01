// lib/app/stored_data_caches.dart
//
// The one reset that Clear all data and a restore both run.
//
// Most of Mantle's providers are autoDispose and die with their screen, and
// every screen re-reads the database when it is built again. Settings is the
// exception that matters: it is pushed over Home, so Home, and whatever Home
// watches, stays alive while the household clears or restores data. A cache
// that Home keeps alive would otherwise go on showing data that is gone,
// such as "Continue the round" for a round that no longer exists.
//
// test/app/stored_data_caches_test.dart fails if a provider that can outlive
// its screen and holds stored data is missing from [storedDataCaches].

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:openhearth_design/openhearth_design.dart';

import '../features/ranking/data/unfinished_round.dart';

/// Every provider that can hold a copy of stored data while Settings is open.
/// Clear all data and a restore both invalidate each one.
final List<ProviderOrFamily> storedDataCaches = [
  // Watched by Home, which stays alive under Settings.
  roundResumeOfferProvider,
];

/// The Undo for Clear all data. It brings back the safety copy, so it must
/// end when the data is replaced another way: a restore of a different
/// backup, then Undo, would put the older safety copy over the restore.
///
/// A provider, not a field of the Settings screen, so the restore hook can
/// reach it. autoDispose, so it lives only as long as Settings, as before.
final clearAllDataUndoProvider = Provider.autoDispose<OhUndoController>(
  (ref) {
    final controller = OhUndoController();
    ref.onDispose(controller.dispose);
    return controller;
  },
  name: 'clearAllDataUndoProvider',
);

/// The one reset. Ends a pending Clear all data Undo first, then reloads
/// every cache in [storedDataCaches].
///
/// Ending the Undo uses `cancel()`, which runs neither the entry's onUndo nor
/// its onCommit, so the reset does not depend on what an offer carries.
void forgetCachedData(
  void Function(ProviderOrFamily provider) invalidate, {
  OhUndoController? undo,
}) {
  undo?.cancel();
  for (final provider in storedDataCaches) {
    invalidate(provider);
  }
}

/// The backup config's onAfterRestore. It only reads the Undo when Settings
/// already holds one, so it never makes a new controller.
void afterMantleRestore(Ref ref) {
  forgetCachedData(
    ref.invalidate,
    undo: ref.exists(clearAllDataUndoProvider)
        ? ref.read(clearAllDataUndoProvider)
        : null,
  );
}
