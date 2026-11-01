// lib/features/timer/presentation/stop_and_report.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';

/// What every STOP button does: stop, save, and say what happened. One
/// function for the Timer and Flow screens, Running and Paused, so the four
/// buttons cannot drift apart again.
///
/// A failed save leaves the session in the unsaved-session panel (see
/// TimerNotifier.stopAndSave) and says "Couldn’t save the session". It never
/// says "Session saved" unless the session is saved (owner, board-0167).
Future<void> stopAndReport(BuildContext context, TimerNotifier notifier) async {
  final result = await notifier.stopAndSave();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  result.fold(
    (failure) {
      debugPrint("Couldn't save the session: ${failure.message}");
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t save the session')),
      );
    },
    (session) => messenger.showSnackBar(SnackBar(
      content: const Text('Session saved'),
      // Add notes is a convenience: the line lapses (C14).
      persist: false,
      action: SnackBarAction(
        label: 'Add notes',
        onPressed: () =>
            context.push('/sessions/${session.id}/edit', extra: session),
      ),
    )),
  );
}
