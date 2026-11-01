import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../engine/engine_providers.dart';
import '../router/app_router.dart';

/// Every long-lived provider that keeps a copy of stored data in memory. A
/// restore, or a hatcher's removal, changes the database behind them, so
/// each path resets this whole list through [forgetCachedData]. One list, so
/// a new cache cannot be left out of one path; `stored_data_caches_test.dart`
/// fails if a keepAlive provider in lib/ is in neither list here.
///
/// The Drift watch streams (profiles, soundMuted) are not here: they follow
/// the database by themselves. The active profile id is not here either: it
/// is device state in SharedPreferences, kept on purpose, and HomeScreen
/// sends a stale id back to the picker.
final List<ProviderOrFamily> storedDataCaches = [
  // Each profile's mastery engine, loaded once from its snapshot. Left
  // alone, it shows the old critters and saves the old progress over the
  // restored snapshot on the next answer.
  engineServiceProvider,
];

/// keepAlive providers that hold no stored data, so nothing to reset.
final List<ProviderOrFamily> keepAliveWithoutStoredData = [
  // Sound cues; the mute flag it listens to is a Drift stream.
  audioServiceProvider,
  // The router: keepAlive on riverpod 3 so its ref outlives the last watcher.
  // It holds where the screen is, not stored data.
  appRouterProvider,
];

/// Forgets every cached copy of stored data, so each one reloads from the
/// database on its next read. Resetting the engine disposes the old one, and
/// a disposed engine refuses to save (see `EngineService.dispose`), so an
/// answer still in flight cannot write old progress back.
///
/// [invalidate] is `ref.invalidate` from either kind of ref (the restore
/// hook has a `Ref`, the picker a `WidgetRef`); Riverpod gives them no
/// common supertype.
void forgetCachedData(void Function(ProviderOrFamily) invalidate) {
  storedDataCaches.forEach(invalidate);
}
