import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:furrow/core/providers/stored_data_caches.dart';

/// Encrypted-backup wiring (sanctuary_backup_ui). Furrow is a new app to
/// this feature, so it gets its own isolated key material (appDomain
/// 'furrow') and its own AEAD context, with no legacy-compat constraint like
/// Lullaby's (SANCTUARY-BRIEF §2.1, §2.3, §4.W2). Lives here, not inline in
/// main(), so tests can run the real restore hook.
const furrowBackupConfig = SanctuaryBackupConfig(
  appId: 'furrow',
  aadContext: 'furrow-backup/v1',
  appDisplayName: 'Furrow',
  restoreReplaceConsequence:
      'Restoring will delete all current habits, marks, and '
      'earned awards on this device, then replace them with data '
      'from the backup file.',
  onAfterRestore: afterFurrowRestore,
);

/// The Today/Garden/Stats/Settings screens watch Drift streams that
/// refresh themselves on the restore's table writes (it runs through the
/// same appDatabaseProvider, never a second handle), so they need nothing.
/// The state outside them (the app-wide "Removed" Undo, the awards waiting
/// for confetti) could write or show pre-restore data: reset it all through
/// the one list.
void afterFurrowRestore(Ref ref) => forgetCachedData(ref);
