import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../core/providers.dart';
import '../core/retry_policy.dart';
import '../features/sanctuary_backup/data/backup_serializer.dart';
import 'stored_data_caches.dart';

/// Mantle's backup wiring (sanctuary_backup_ui). Public so tests run the
/// real config, restore hook included, instead of a copy of it.
///
/// Mantle is greenfield here: its own isolated key material (appDomain
/// 'mantle') and its own AEAD context, so a Mantle blob can never decrypt
/// under another app's context (SANCTUARY-BRIEF §2.1, §2.3).
const mantleBackupConfig = SanctuaryBackupConfig(
  appId: 'mantle',
  aadContext: 'mantle-backup/v1',
  appDisplayName: 'Mantle',
  restoreReplaceConsequence:
      'Restoring will delete all household members, ranking '
      'rounds, charters, and solo/tutor progress on this device, '
      'then replace them with data from the backup file.',
  // Home stays alive under Settings, where restores happen, so what it
  // caches must be reset, and a pending Clear all data Undo must end.
  onAfterRestore: afterMantleRestore,
);

/// The root `ProviderScope` overrides for the running app. [web] exists for
/// tests; the app always uses the platform default.
List<Override> mantleRootOverrides({bool web = kIsWeb}) => [
      sanctuaryAppDomainProvider.overrideWithValue('mantle'),
      sanctuaryBackupConfigProvider.overrideWithValue(mantleBackupConfig),
      // On web every fleet PWA shares one origin, so the recovery words go
      // under Mantle's own key names; native keeps the platform keychain.
      appScopedKeyStoreOverride(web: web),
      backupSerializerProvider.overrideWith(
        (ref) => MantleBackupSerializer(ref.watch(databaseProvider)),
      ),
    ];

/// The app's root scope. main() builds it, and so do the tests that pin what
/// the root decides, so the policy is tested where it applies.
///
/// [noAutoRetry] is set here for every provider, including those from the
/// shared backup packages, which build against riverpod 2 as well and so
/// cannot name a retry policy of their own.
ProviderScope mantleProviderScope({
  required Widget child,
  List<Override>? overrides,
  Key? key,
}) =>
    ProviderScope(
      key: key,
      retry: noAutoRetry,
      overrides: overrides ?? mantleRootOverrides(),
      child: child,
    );
