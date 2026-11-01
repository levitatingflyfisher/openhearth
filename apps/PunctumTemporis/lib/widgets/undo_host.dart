import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openhearth_design/openhearth_design.dart';

import '../models/clip.dart';
import '../services/storage_service.dart';

// The delete policy, in one place (fleet ruling, 2026-09-26):
//
// * A DELIBERATE delete (the Delete button on a clip, the delete on a saved
//   montage, "Remove this entry" on a missing clip) does not ask. It
//   happens at once and offers Undo through the bar below, which never
//   times out: it stays until the person taps Undo, dismisses it, or deletes
//   something else.
// * An EASY gesture that deletes would ask first with showOhConfirm naming
//   the thing. PT has none today (no swipe deletes a clip or a montage).
//
// The delete itself is soft (StorageService.removeClip/removeCompilation).
// A clip cannot be made again, so it stays pending, row and files, when
// the offer lapses or the app is killed. Settings > Recently deleted
// offers Restore, and the next start's note points there. Only "Delete for
// good", confirmed, destroys it (owner ruling, board-0124). A montage gets
// the same protection (owner ruling, board-0138).
//
// A restore ends the offer the same way a dismissed bar does: the item
// stays in Recently deleted, and Undo cannot put it into the restored
// journal (_forgetCachedData in main.dart).

/// The one Undo offer for the whole app.
///
/// A clip's delete closes the screen it happens on (the preview pops back
/// to the day or the calendar), so a bar placed on that screen would vanish
/// with it. The controller lives as long as the app, and [UndoHost] shows
/// its bar below every screen.
class UndoHost extends StatefulWidget {
  const UndoHost({super.key, required this.controller, required this.child});

  final OhUndoController controller;
  final Widget child;

  /// The app's controller, or null outside an [UndoHost] (a screen pumped
  /// alone in a test).
  static OhUndoController? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_UndoScope>()
      ?.controller;

  @override
  State<UndoHost> createState() => _UndoHostState();
}

class _UndoHostState extends State<UndoHost> {
  // The bar's buttons carry tooltips, which need an Overlay; the navigator's
  // own overlay sits below this widget, so the host brings one.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildFrame);

  @override
  void didUpdateWidget(UndoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child ||
        oldWidget.controller != widget.controller) {
      _entry.markNeedsBuild();
    }
  }

  Widget _buildFrame(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final showing = controller.pending != null;
        return Column(
          children: [
            Expanded(
              // While the bar shows it takes the bottom safe area, so the
              // screen above does not pad for the gesture bar a second time.
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: showing,
                child: widget.child,
              ),
            ),
            OhUndoBar(controller: controller, commitOnDispose: false),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _UndoScope(
      controller: widget.controller,
      child: Overlay(initialEntries: [_entry]),
    );
  }
}

class _UndoScope extends InheritedWidget {
  const _UndoScope({required this.controller, required super.child});

  final OhUndoController controller;

  @override
  bool updateShouldNotify(_UndoScope old) => old.controller != controller;
}

/// "Sep 4, 2026": how the delete wording names a clip's day.
String clipDayLabel(Clip clip) =>
    DateFormat('MMM d, yyyy').format(DateTime.parse(clip.date));

/// Deletes [clip] at once and offers Undo in the app-wide bar.
///
/// Read the controller before awaiting anything: the widget that asked
/// usually leaves the tree with the delete. The clip stays pending when the
/// offer lapses, and outside an [UndoHost] (a screen pumped alone), and
/// waits in Recently deleted.
Future<void> deleteClipWithUndo(
    BuildContext context, StorageService storage, Clip clip) async {
  final controller = UndoHost.maybeOf(context);
  final removal = await storage.removeClip(clip.id);
  if (removal == null || controller == null) return;
  controller.show(
    message: 'Deleted the clip for ${clipDayLabel(clip)}',
    onUndo: () => storage.restoreClip(removal),
  );
}

/// How the delete wording names a pending clip or montage.
String removalName(Removal removal) => switch (removal) {
      ClipRemoval(:final clip) => 'the clip for ${clipDayLabel(clip)}',
      CompilationRemoval(:final compilation) =>
        'the montage “${compilation.title}”',
      SetAsideFiles(isMontage: false) =>
        'a clip file kept from an older version',
      SetAsideFiles(isMontage: true) =>
        'a montage file kept from an older version',
    };

/// Asks before destroying a pending clip or montage, naming it. Returns
/// whether the owner confirmed; only then do its files go.
Future<bool> confirmDeleteForGood(
    BuildContext context, StorageService storage, Removal removal) async {
  final confirmed = await showOhConfirm(
    context,
    title: 'Delete ${removalName(removal)} for good?',
    message: 'Its video leaves this device. You cannot undo this.',
    confirmLabel: 'Delete for good',
    destructive: true,
  );
  if (!confirmed) return false;
  await storage.deleteForGood(removal);
  return true;
}

/// Deletes a saved montage at once and offers Undo in the app-wide bar.
/// The montage stays pending when the offer lapses, and outside an
/// [UndoHost], like a clip.
Future<void> deleteCompilationWithUndo(BuildContext context,
    StorageService storage, Compilation compilation) async {
  final controller = UndoHost.maybeOf(context);
  final removal = await storage.removeCompilation(compilation.id);
  if (removal == null || controller == null) return;
  controller.show(
    message: 'Deleted the montage “${compilation.title}”',
    onUndo: () => storage.restoreCompilation(removal),
  );
}

/// Asks once per start about deleted items more than
/// [StorageService.deletedKeepDays] days old. Nothing is destroyed on a
/// timer (a clip goes only after its owner really confirms), so this is
/// that confirm, naming how many. Keep, or closing the question, leaves
/// them and their files, and they are asked about again after another
/// [StorageService.deletedKeepDays] days.
Future<void> askAboutOldDeletes(
    BuildContext context, StorageService storage) async {
  if (storage.oldRemovalsAsked) return;
  final old = storage.oldRemovals;
  if (old.isEmpty) return;
  storage.oldRemovalsAsked = true;
  const days = StorageService.deletedKeepDays;
  final one = old.length == 1;
  final confirmed = await showOhConfirm(
    context,
    title: one
        ? '1 deleted item is more than $days days old. Delete it for good?'
        : '${old.length} deleted items are more than $days days old. '
            'Delete them for good?',
    message: one
        ? 'Its video leaves this device. You cannot undo this.'
        : 'Their videos leave this device. You cannot undo this.',
    confirmLabel: 'Delete for good',
    cancelLabel: 'Keep',
    destructive: true,
  );
  if (confirmed) {
    await storage.deleteForGoodAll(old);
  } else {
    await storage.keepForNow(old);
  }
}
