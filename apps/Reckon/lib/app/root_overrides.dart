import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../core/database/database_providers.dart';
import '../core/providers/retry_policy.dart';
import '../features/case/data/case_providers.dart';
import '../features/outside_view/data/outside_view_providers.dart';
import '../features/predictions/data/prediction_providers.dart';
import '../features/record/data/record_providers.dart';
import '../features/sanctuary_backup/data/backup_serializer.dart';

/// The app's root scope. main() builds it, and so does the test that pins
/// what the root decides, so the policy is tested where it applies.
///
/// [noAutoRetry] is set here for every provider, including those of the
/// shared backup packages, which build against riverpod 2 as well and so
/// cannot name a retry policy of their own. Without it a locked keychain
/// would sit behind a spinner while riverpod 3 retried it.
ProviderScope reckonProviderScope({
  required Widget child,
  List<Override>? overrides,
  Key? key,
}) =>
    ProviderScope(
      key: key,
      retry: noAutoRetry,
      overrides: overrides ?? reckonRootOverrides(),
      child: child,
    );

/// The root `ProviderScope` overrides for the running app. [web] exists for
/// tests; the app always uses the platform default.
List<Override> reckonRootOverrides({bool web = kIsWeb}) => [
      // Encrypted-backup wiring (sanctuary_backup_ui). Reckon is a new
      // consumer, so it gets its own isolated key material (appDomain
      // 'reckon') and its own AEAD context — a blob can never cross apps
      // (SANCTUARY-BRIEF §2.1, §2.3, §4.W2). Party sync
      // (features/party/sync/party_crypto.dart) is untouched by this —
      // it is a separate, ephemeral, link-carried key system.
      sanctuaryAppDomainProvider.overrideWithValue('reckon'),
      sanctuaryBackupConfigProvider.overrideWithValue(
        SanctuaryBackupConfig(
          appId: 'reckon',
          aadContext: 'reckon-backup/v1',
          appDisplayName: 'Reckon',
          restoreReplaceConsequence:
              'Restoring will delete every decision, weigh-in, outside view, '
              'resolution, model prediction, and your profile currently '
              'on this device, then replace them with the contents of '
              'the backup file. It does not touch your groups, group votes or '
              'the forecaster list; those are not part of this backup.',
          // Restore replaces the case-scoped tables directly through
          // AppDatabase; the Drift watch streams (open cases) self-refresh,
          // but these FutureProviders cache a snapshot and don't — every
          // one must be invalidated or the record/detail screens keep
          // showing wiped rows (SANCTUARY-BRIEF §2.5).
          onAfterRestore: (ref) {
            ref.invalidate(closedCaseRecordsProvider);
            ref.invalidate(clarityScoreProvider);
            ref.invalidate(insightCardsProvider);
            ref.invalidate(closedCasesProvider);
            ref.invalidate(calibrationReportProvider);
            ref.invalidate(personalBaseRatesProvider);
            ref.invalidate(updateQualityProvider);
            ref.invalidate(forecasterWeightsProvider);
            ref.invalidate(caseByIdProvider);
            ref.invalidate(pollsForCaseProvider);
            ref.invalidate(outsideViewForCaseProvider);
            ref.invalidate(duelForecastsForCaseProvider);
          },
        ),
      ),
      backupSerializerProvider.overrideWith(
        (ref) => ReckonBackupSerializer(ref.watch(appDatabaseProvider)),
      ),
      // On web every fleet PWA shares one origin, so the recovery words go
      // under Reckon's own key names; native keeps the platform keychain.
      appScopedKeyStoreOverride(web: web),
    ];
