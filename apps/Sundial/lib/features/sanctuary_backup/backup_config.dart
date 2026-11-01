import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sundial/core/providers/stored_data_caches.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';

/// Encrypted-backup wiring (sanctuary_backup_ui). Sundial is a NEW
/// sanctuary app, so it gets its own isolated key material via appDomain
/// (SANCTUARY-BRIEF §2.1) rather than the legacy household-wide derivation
/// Lullaby keeps for compatibility. Lives here, not inline in main(), so
/// tests can run the real restore hook.
const sundialBackupConfig = SanctuaryBackupConfig(
  appId: 'sundial',
  aadContext: 'sundial-backup/v1',
  appDisplayName: 'Sundial',
  restoreReplaceConsequence:
      'Restoring will delete all current profiles, sessions, and '
      'earned badges on this device, then replace them with the '
      'contents of the backup file. A running timer stops without '
      'saving.',
  onAfterRestore: afterSundialRestore,
);

/// Drift's watch streams self-refresh after the destructive restore. The
/// long-lived state outside them (the timer, both Undo offers, the selected
/// profile) can still point at wiped rows, or write them back: reset it all
/// through the one list, then redraw the home-screen widget from the
/// restored record. The widget comes last so it no longer counts the ended
/// timer's time.
void afterSundialRestore(Ref ref) {
  forgetCachedData(ref);
  final today = DateTime.now();
  final todayKey = '${today.year}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  unawaited(ref.read(timerProvider.notifier).refreshWidget(todayKey));
}
