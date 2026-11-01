import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/stored_data_caches.dart';
import '../../services/backup/still_life_backup_serializer.dart';

/// Root-scope overrides that wire the generic `sanctuary_backup_ui` to
/// StillLife (SANCTUARY-BRIEF §4.W3). Applied on the `ProviderContainer` in
/// `main.dart`. [web] is for tests; it defaults to the real platform.
/// A test that brings its own key store passes [appKeyStore] false:
/// riverpod 3 refuses two overrides of one provider in one container.
List<Override> sanctuaryBackupOverrides({
  bool web = kIsWeb,
  bool appKeyStore = true,
}) => [
  sanctuaryBackupConfigProvider.overrideWithValue(
    SanctuaryBackupConfig(
      appId: 'stilllife',
      // A blob for this context can never be decrypted under another app's
      // (§2.3). Distinct from the LAN-sync 'stilllife-lan/v1' context.
      aadContext: 'stilllife-backup/v1',
      appDisplayName: 'Still Life',
      // Honest copy: the metadata restore is an upsert-merge, NOT a wipe —
      // photo BLOBs the backup omits are preserved, and items added since the
      // backup remain. Do not imply the database will match the backup exactly.
      restoreReplaceConsequence:
          'Restoring merges this backup into Still Life on this device, '
          'overwriting any records that share an id. Photos already on this '
          'device are kept, and items you added since the backup stay put.',
      // The package defaults ('Replace all data?' / 'Replace everything')
      // describe a destructive replace — over a merge they'd be a dark
      // pattern in reverse: scarier than the truth. backup_config.dart
      // requires merge apps to override both.
      confirmTitle: 'Merge backup into this device?',
      confirmActionLabel: 'Merge backup',
      // Lists are Drift watch streams and one-shot reads re-read on every
      // write, so both follow the merge. What cannot, the Undo offers above
      // all, is reset here (see stored_data_caches.dart).
      onAfterRestore: (ref) => forgetCachedData(ref.invalidate, ref.read),
    ),
  ),
  backupSerializerProvider.overrideWith(
    (ref) => StillLifeBackupSerializer(
      exportService: ref.watch(exportServiceProvider),
      importService: ref.watch(importServiceProvider),
    ),
  ),
  // Isolate StillLife's key material from any other app sharing a household
  // seed (§2.1).
  sanctuaryAppDomainProvider.overrideWithValue('stilllife'),
  // On the web every fleet PWA shares one origin's storage, so the recovery
  // words get StillLife's own key names (sanctuary_backup_ui 0.3.0). Native
  // keeps the per-app keychain unchanged.
  if (appKeyStore) appScopedKeyStoreOverride(web: web),
];
