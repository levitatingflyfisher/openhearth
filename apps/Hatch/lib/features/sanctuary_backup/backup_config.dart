import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../core/providers/stored_data_caches.dart';

/// Encrypted-backup wiring (sanctuary_backup_ui). Hatch is new to the
/// feature, so it gets its own isolated key material (appDomain 'hatch') and
/// its own AEAD context, with no legacy-compat constraint. Lives here, not
/// inline in main(), so tests can run the real restore hook.
const hatchBackupConfig = SanctuaryBackupConfig(
  appId: 'hatch',
  aadContext: 'hatch-backup/v1',
  appDisplayName: 'Hatch',
  // Restore is a full destructive replace; the dialog copy says exactly
  // that, per-app rather than the package's generic line.
  confirmTitle: 'Replace every nest?',
  confirmActionLabel: 'Replace everything',
  restoreReplaceConsequence:
      'Restoring will delete every hatcher profile, their critters '
      'and hatching progress, and all practice history on this '
      'device, then replace them with the data in the backup file.',
  onAfterRestore: afterHatchRestore,
);

/// A restore replaces every profile, snapshot and setting. The Drift
/// streams (profiles, soundMuted) follow the database by themselves; the
/// cached engines do not, so they are forgotten here. The active-profile id
/// lives in SharedPreferences and may now point at a profile the backup does
/// not contain; HomeScreen detects the stale id and returns to the picker.
void afterHatchRestore(Ref ref) => forgetCachedData(ref.invalidate);
