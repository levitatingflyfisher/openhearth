// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/providers/retry_policy.dart';
import 'package:sundial/core/router/app_router.dart';
import 'package:sundial/features/move/move_page.dart';
import 'package:sundial/features/sanctuary_backup/backup_config.dart';
import 'package:sundial/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:sundial/features/timer/data/auto_stop_service.dart';
import 'package:sundial/features/timer/data/timer_notification_service.dart'
    show initTimerNotifications, mediaSessionChannel;
import 'package:sundial/features/timer/domain/timer_state.dart';
import 'package:sundial/features/timer/presentation/timer_notifier.dart';
import 'package:sundial/shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write.
  if (ohMovePage) {
    runApp(MovePageApp(
      overrides: sundialBackupOverrides(),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
    ));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await initTimerNotifications();
  runApp(
    sundialProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...sundialBackupOverrides(),
      ],
      child: const SundialApp(),
    ),
  );
}

/// Backup wiring, shared by the app and the move page build.
List<Override> sundialBackupOverrides() => [
      // Own key material via appDomain; the config and its restore hook
      // live in backup_config.dart.
      sanctuaryAppDomainProvider.overrideWithValue('sundial'),
      sanctuaryBackupConfigProvider.overrideWithValue(sundialBackupConfig),
      // Web PWAs share one github.io origin: keep Sundial's recovery words
      // in Sundial's own key-store namespace (no-op on native).
      appScopedKeyStoreOverride(),
      backupSerializerProvider.overrideWith(
        (ref) => SundialBackupSerializer(ref.watch(appDatabaseProvider)),
      ),
    ];

class SundialApp extends ConsumerStatefulWidget {
  const SundialApp({super.key});

  @override
  ConsumerState<SundialApp> createState() => _SundialAppState();
}

class _SundialAppState extends ConsumerState<SundialApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () async {
        await _checkAutoStop();
        await _refreshWidget();
      },
    );
    // Attach the lifecycle observer that clears the widget-launch override on
    // app pause. Reading the provider has a side-effect registration.
    ref.read(widgetLaunchLifecycleObserverProvider);
    // Silent freshness snapshot (BACKUP_RETENTION_SPEC §3): if the newest
    // vault snapshot is >7 days old and a key exists, take one. Post-frame
    // + fire-and-forget — never blocks boot, never surfaces errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupControllerProvider.notifier).runStartupMaintenance();
    });
    // Listen for host → Dart "launchSource" calls from MainActivity.kt. When
    // the user taps the home-screen widget, flip into the transient Flow
    // override so AppShell renders FlowScreen regardless of the durable
    // AppMode preference.
    mediaSessionChannel.setMethodCallHandler((call) async {
      if (call.method == 'launchSource') {
        final source = (call.arguments as Map?)?['source'] as String?;
        if (source == 'widget') {
          ref.read(widgetLaunchOverrideProvider.notifier).set(true);
        }
      } else if (call.method == 'timerAction') {
        final args = call.arguments as Map?;
        final action = args?['action'] as String?;
        final notifier = ref.read(timerProvider.notifier);
        final timerState = ref.read(timerProvider);
        switch (action) {
          case 'pause':
            if (timerState is TimerRunning) {
              await notifier.pause(fromNative: true);
            }
          case 'resume':
            if (timerState is TimerPaused) {
              await notifier.resume(fromNative: true);
            }
          case 'stop':
            if (timerState is TimerRunning || timerState is TimerPaused) {
              await notifier.stopAndSave(fromNative: true);
            }
        }
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshWidget());
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _refreshWidget() async {
    try {
      final now = DateTime.now();
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await ref.read(timerProvider.notifier).refreshWidget(todayKey);
    } catch (_) {}
  }

  Future<void> _checkAutoStop() async {
    final prefs = await ref.read(settingsRepositoryProvider).getUserPrefs();
    if (!prefs.autoStopEnabled) return;

    final sharedPrefs = ref.read(sharedPreferencesProvider);
    final startMs = sharedPrefs.getInt('timer_start_ms');

    if (AutoStopService.shouldTrigger(
      timerStartMs: startMs,
      thresholdHours: prefs.autoStopThresholdHours,
    )) {
      await ref.read(timerProvider.notifier).autoStopAndSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Sundial',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // No app-wide width box: each screen caps its own content with OhPage
      // (640dp, centred), so app bars and bottom bars stay full width.
      routerConfig: router,
      // On the web the data lives in this browser: say so above every screen.
      builder: ohWebDataNoticeBuilder,
    );
  }
}
