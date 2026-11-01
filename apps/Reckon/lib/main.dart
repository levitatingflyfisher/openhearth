import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/root_overrides.dart';
import 'app/startup_failure.dart';
import 'core/auth/auth_providers.dart';
import 'core/database/database_providers.dart';
import 'core/llm/gemma_init.dart';
import 'core/notifications/notification_providers.dart';
import 'features/move/move_page.dart';
import 'shared/theme/reckon_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before the model runtime, the seeding or anything else
  // at the normal start can write.
  if (ohMovePage) {
    runApp(MovePageApp(
      overrides: reckonRootOverrides(),
      theme: ReckonTheme.light(),
      darkTheme: ReckonTheme.hearthDark(),
    ));
    return;
  }
  // flutter_gemma 0.13.x requires this one-time init before installModel /
  // getActiveModel are used — without it, starting a case throws
  // "Bad state: FlutterGemma not initialized!". Platform-selected so the web
  // build (which has no model runtime) skips it and never imports flutter_gemma.
  await initGemma();
  // The root scope never retries a failed provider on its own: a failed
  // startup read must reach StartupFailure, not sit behind the spinner.
  runApp(reckonProviderScope(child: const _Bootstrap()));
}

class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(seedReferenceClassesProvider);
    final notif = ref.watch(initNotificationsProvider);
    final onboarded = ref.watch(onboardingCompleteProvider);

    if (seed.isLoading || notif.isLoading || onboarded.isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (seed.hasError || notif.hasError || onboarded.hasError) {
      final failed = seed.hasError
          ? seed
          : notif.hasError
              ? notif
              : onboarded;
      debugPrint('Reckon: startup failed: ${failed.error}');
      return StartupFailure(
          error: failed.error!, stackTrace: failed.stackTrace);
    }
    return const ReckonApp();
  }
}
