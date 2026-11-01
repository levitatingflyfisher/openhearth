// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/providers/retry_policy.dart';
import 'package:furrow/core/router/app_router.dart';
import 'package:furrow/features/move/move_page.dart';
import 'package:furrow/features/sanctuary_backup/backup_config.dart';
import 'package:furrow/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:furrow/shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write.
  if (ohMovePage) {
    runApp(MovePageApp(
      overrides: furrowBackupOverrides(),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
    ));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    furrowProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...furrowBackupOverrides(),
      ],
      child: const FurrowApp(),
    ),
  );
}

/// Encrypted-backup wiring, with the restore hook (see backup_config.dart),
/// shared by the app and the move page build.
List<Override> furrowBackupOverrides() => [
      sanctuaryAppDomainProvider.overrideWithValue('furrow'),
      sanctuaryBackupConfigProvider.overrideWithValue(furrowBackupConfig),
      // Web only: prefix the recovery-word keys with Furrow's app id, so
      // fleet PWAs sharing one origin never share (or overwrite) each
      // other's words. Native keychains are per-app already.
      appScopedKeyStoreOverride(),
      backupSerializerProvider.overrideWith(
        (ref) => FurrowBackupSerializer(ref.watch(appDatabaseProvider)),
      ),
    ];

class FurrowApp extends ConsumerStatefulWidget {
  const FurrowApp({super.key});

  @override
  ConsumerState<FurrowApp> createState() => _FurrowAppState();
}

class _FurrowAppState extends ConsumerState<FurrowApp> {
  @override
  void initState() {
    super.initState();
    // Silent freshness snapshot (BACKUP_RETENTION_SPEC §3): if a key exists
    // and the newest vault snapshot is stale, take one. Post-first-frame +
    // fire-and-forget — never blocks boot, never surfaces errors (the same
    // hook Sundial and Lullaby run at startup).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupControllerProvider.notifier).runStartupMaintenance();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Furrow',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Wide screens: each screen caps its own body with OhPage, so app
      // bars and backgrounds stay full width and only the content centres.
      routerConfig: router,
      // On the web the data lives in this browser: say so above every screen.
      builder: ohWebDataNoticeBuilder,
    );
  }
}
