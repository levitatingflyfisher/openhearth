// Destructive settings actions. Kept out of the widget so the erase path is a
// single, testable unit: wipe the tables, cancel reminders, refresh every
// keepAlive read model, then await the (now-null) profile so the router's
// redirect is ready to bounce back to onboarding before the caller navigates.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import 'package:bulwark/core/providers/core_providers.dart';
import 'package:bulwark/features/adoption/domain/notification_planner.dart';
import 'package:bulwark/features/adoption/presentation/providers.dart';
import 'package:bulwark/features/library/data/content_loader.dart';
import 'package:bulwark/features/notifications/notification_providers.dart';
import 'package:bulwark/shared/widgets/undo_host.dart';

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

/// Erase every habit, check-in, pulse, shopping state, and the profile, then
/// cancel all reminders. Shell prefs (theme, reminders switch) survive. The
/// caller navigates to `/onboarding` once this resolves.
Future<void> eraseAllData(WidgetRef ref) async {
  await ref.read(appDatabaseProvider).eraseUserData();

  // Cancel all scheduled reminders (empty plan = cancelAll). Best-effort: a
  // notification-platform failure must not abort the wipe the user asked for.
  try {
    await ref.read(notificationServiceProvider).reschedule(const []);
  } catch (_) {}

  await _forgetCachedData(ref.invalidate, ref.read(undoControllerProvider));

  // Wait for the profile to resolve to null so the redirect holds still (it
  // only acts once the async has a value) when the caller pushes onboarding.
  await ref.read(profileProvider.future);
}

/// The `Ref`-typed hook `SanctuaryBackupConfig.onAfterRestore` runs after a
/// destructive encrypted-backup restore (SANCTUARY-BRIEF §4.W2). It forgets
/// the same cached data as [eraseAllData], through the same
/// [_forgetCachedData]; only the reminder replan below differs.
///
/// Unlike erase, a restore can *reintroduce* reminder-eligible habits, so
/// this recomputes the day's plan from the restored data instead of
/// rescheduling blank. Returns a [Future] (rather than firing-and-forgetting
/// internally, like [eraseAllData] does) so callers can await it directly in
/// tests; the production `onAfterRestore` wraps the call in `unawaited()`.
Future<void> afterBackupRestore(Ref ref) async {
  await _forgetCachedData(ref.invalidate, ref.read(undoControllerProvider));

  // Best-effort, mirroring eraseAllData's reschedule: a scheduling failure
  // must not surface to the user or undo the restore that already
  // succeeded.
  try {
    final service = ref.read(notificationServiceProvider);
    final prefs = await ref.read(settingsRepositoryProvider).getUserPrefs();
    final profile = await ref.read(profileProvider.future);
    if (!prefs.remindersEnabled || profile == null) {
      await service.reschedule(const []);
      return;
    }
    final library = await ref.read(contentLibraryProvider.future);
    final active =
        await ref.read(habitStateRepositoryProvider).activeStates();
    final planned = const NotificationPlanner()
        .plan(profile: profile, active: active, library: library);
    await service.reschedule(planned);
  } catch (_) {}
}

/// Erase and restore both swap the data under the app, so both forget every
/// cached copy of it, through this one function so the two cannot drift
/// apart. Each read model in [storedDataReadModels] reloads. A pending Undo
/// is cancelled, never undone and never committed: it holds a habit's state
/// from before, and tapping it would write that state back into the erased or
/// restored data. cancel() runs neither onUndo nor onCommit.
/// [invalidate] is `ref.invalidate` from either kind of ref (a `WidgetRef`
/// for erase, a `Ref` for restore); Riverpod gives them no common supertype.
Future<void> _forgetCachedData(
  void Function(ProviderBase<AsyncValue<Object?>>) invalidate,
  OhUndoController undo,
) async {
  storedDataReadModels.forEach(invalidate);
  undo.cancel();
}
