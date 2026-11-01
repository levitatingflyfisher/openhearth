import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/stored_data_caches.dart';
import '../home_widget/presentation/controllers/home_widget_controller.dart';

/// Runs after a destructive restore (`SanctuaryBackupConfig.onAfterRestore`).
///
/// The Drift watch streams refresh themselves, but in-memory state can still
/// point at wiped rows: the running timers, the last export, and any pending
/// Undo, which would put a row from the old record into the restored one.
/// [forgetCachedData] resets them all, then the home widget is redrawn from
/// the restored database.
void lullabyAfterRestore(Ref ref) {
  forgetCachedData(ref);
  unawaited(ref.read(homeWidgetControllerProvider).triggerUpdate());
}
