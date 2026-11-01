import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers/database_provider.dart';
import '../core/providers/settings_providers.dart';
import '../features/sanctuary_backup/data/backup_serializer.dart';
import 'stored_data_caches.dart';

/// The root `ProviderScope` overrides, here rather than inline in `main()`
/// so a test can build the same scope. [web] is for tests only.
List<Override> liltRootOverrides({
  required SharedPreferences prefs,
  bool web = kIsWeb,
}) =>
    [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Encrypted-backup wiring (sanctuary_backup_ui). Lilt is a new app,
      // so it gets its own isolated key material (appDomain 'lilt') and its
      // own AEAD context — no legacy-compat constraint like Lullaby's
      // (SANCTUARY-BRIEF §2.1, §2.3, §4.W2).
      sanctuaryAppDomainProvider.overrideWithValue('lilt'),
      sanctuaryBackupConfigProvider.overrideWithValue(
        SanctuaryBackupConfig(
          appId: 'lilt',
          aadContext: 'lilt-backup/v1',
          appDisplayName: 'Lilt',
          restoreReplaceConsequence:
              'Restoring will delete all custom names, ranking sessions, '
              'comparison history, and your shortlist on this device, then '
              'replace them with data from the backup file. The bundled '
              'name catalog is not affected.',
          // Resets every cached read and ends a pending Clear Undo.
          onAfterRestore: afterLiltRestore,
        ),
      ),
      // Fleet PWAs share one browser origin, so on web the recovery words
      // are stored under Lilt's own keys, never a sibling app's.
      appScopedKeyStoreOverride(web: web),
      backupSerializerProvider.overrideWith(
        (ref) => LiltBackupSerializer(ref.watch(databaseProvider)),
      ),
    ];

