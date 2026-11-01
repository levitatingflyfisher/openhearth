// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hatch/core/engine/engine_providers.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/providers/retry_policy.dart';
import 'package:hatch/core/router/app_router.dart';
import 'package:hatch/features/move/move_page.dart';
import 'package:hatch/features/sanctuary_backup/backup_config.dart';
import 'package:hatch/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:hatch/shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write.
  if (ohMovePage) {
    runApp(MovePageApp(
      overrides: hatchBackupOverrides(),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
    ));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    hatchProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...hatchBackupOverrides(),
      ],
      child: const HatchApp(),
    ),
  );
}

/// Backup wiring, shared by the app and the move page build.
List<Override> hatchBackupOverrides({bool web = kIsWeb}) => [
      sanctuaryAppDomainProvider.overrideWithValue('hatch'),
      sanctuaryBackupConfigProvider.overrideWithValue(hatchBackupConfig),
      // On the web every fleet app shares one origin's localStorage: keep
      // Hatch's recovery words under Hatch's own name. Words under the old
      // shared name are taken over only when a snapshot in Hatch's vault
      // proves they are Hatch's, and the old entry is never removed.
      appScopedKeyStoreOverride(web: web),
      backupSerializerProvider.overrideWith(
        (ref) => HatchBackupSerializer(ref.watch(appDatabaseProvider)),
      ),
    ];

class HatchApp extends ConsumerStatefulWidget {
  const HatchApp({super.key});

  @override
  ConsumerState<HatchApp> createState() => _HatchAppState();
}

class _HatchAppState extends ConsumerState<HatchApp> {
  @override
  void initState() {
    super.initState();
    // Silent freshness snapshot: if a key exists and the newest vault
    // snapshot is stale, take one. Post-first-frame + fire-and-forget —
    // never blocks boot, never surfaces errors (the same hook the rest of
    // the fleet runs at startup).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupControllerProvider.notifier).runStartupMaintenance();
      // Kick the audio preload now so cues are warm before the first play;
      // the service itself is never load-bearing (ADR-0003).
      ref.read(audioServiceProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Hatch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      // On the web the data lives in this browser: the fleet notice sits
      // above every screen, around the app's own frame.
      builder: (context, child) =>
          ohWebDataNoticeBuilder(context, _frame(context, child)),
    );
  }

  /// On wide screens keep the single-column app centered at a comfortable
  /// width rather than stretching edge-to-edge (phones pass through).
  Widget _frame(BuildContext context, Widget? child) {
    Widget inner = child ?? const SizedBox.shrink();
    if (MediaQuery.of(context).size.width > 760) {
      inner = ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: SizedBox(width: 760, child: inner)),
      );
    }
    // Web autoplay unlock: prime the audio context inside the first user
    // gesture, app-wide. Retries until a cue is loaded, then latches.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          ref.read(audioServiceProvider).unlockOnFirstGesture(),
      child: inner,
    );
  }
}
