// PorchApp — the root: theme + the onboarding/home gate.
//
// The gate is a pure function of three providers: the launch reads held
// (launchReadsProvider), an identity exists (sessionProvider) and onboarding
// finished (a display name in state). A failed read of any of them is shown
// here, with Try again, and is never read as "nothing yet".
// No routing framework — Porch is three screens deep at most.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart';

import '../data/key_store.dart';
import 'home/home_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'providers.dart';

/// The porch light: warm amber, dusk-friendly. These are the primaries the
/// old `ColorScheme.fromSeed(0xFFB4762A)` rendered, kept as the app accent
/// on the fleet theme. The raw seed itself carries white text at only
/// 3.8:1; these reach 6.4:1 (light) and 9.9:1 (dark) with the theme's own
/// on-primary (theme_test.dart). Recorded for C12 in the conformance config.
const porchAmberLight = Color(0xFF845416);
const porchAmberDark = Color(0xFFFBBA73);

/// The app's root scope, with retry off for every provider under it
/// ([noAutoRetry]). bootstrap uses it, and so do the screen tests, so the
/// tests run under the same policy as the app.
ProviderScope porchProviderScope({
  required List<Override> overrides,
  required Widget child,
}) =>
    ProviderScope(overrides: overrides, retry: noAutoRetry, child: child);

class PorchApp extends ConsumerWidget {
  const PorchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Porch',
      debugShowCheckedModeBanner: false,
      theme: OhTheme.light(appAccent: porchAmberLight),
      darkTheme: OhTheme.hearthDark(appAccent: porchAmberDark),
      themeMode: ref.watch(themeModeProvider).themeMode,
      home: const RootGate(),
      // On the web porch's state lives in this browser: the fleet notice
      // sits above every screen. Home and Settings keep porch's own red Web
      // preview banner about keys as well.
      builder: ohWebDataNoticeBuilder,
    );
  }
}

class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The launch reads (state key, saved relay URL) come first: the state
    // store and the relay endpoint are built from them, so nothing below
    // is watched until they hold.
    final launch = ref.watch(launchReadsProvider);
    if (launch.isLoading) return _loading;
    if (launch.hasError) {
      return _failedRead(launch, () => ref.invalidate(launchReadsProvider));
    }
    final session = ref.watch(sessionProvider);
    final state = ref.watch(porchStateProvider);
    if (session.isLoading || state.isLoading) return _loading;
    // A failed read of the identity or the state file is shown as a
    // failure. On riverpod 3 `.value` is null on a failure, so without this
    // the gate would read it as "no identity yet" or "not onboarded" and
    // show onboarding, whose restore step saves over the unreadable file.
    final AsyncValue<Object?>? failed =
        session.hasError ? session : (state.hasError ? state : null);
    if (failed != null) {
      void retry() {
        if (session.hasError) ref.invalidate(sessionProvider);
        if (state.hasError) ref.invalidate(porchStateProvider);
      }
      final error = session.error;
      if (error is CorruptSecretException &&
          error.key == PorchKeyStore.entropyKey) {
        return _failedRead(failed, retry,
            below: const _RestoreOverGarbledIdentity());
      }
      return _failedRead(failed, retry);
    }
    final hasIdentity = session.value != null;
    final onboarded =
        hasIdentity && (state.value?.profile.displayName.isNotEmpty ?? false);
    if (!onboarded) return OnboardingFlow(hasIdentity: hasIdentity);
    return const HomeScreen();
  }

  static const _loading =
      Scaffold(body: Center(child: CircularProgressIndicator()));

  /// The one view for a failed read of this phone's own data: the fleet's
  /// sentence, the raw error behind Details, and Try again, which reads
  /// again only what failed.
  static Widget _failedRead(AsyncValue<Object?> failed, VoidCallback retry,
          {Widget? below}) =>
      Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OhErrorState.fromError(
                    failed.error!,
                    stackTrace: failed.stackTrace,
                    icon: Icons.error_outline,
                    onRetry: retry,
                  ),
                  ?below,
                ],
              ),
            ),
          ),
        ),
      );
}

/// The way out when this phone's stored identity is garbled: restore from
/// the 12 words or a backup file. Behind a confirm, and the garbled value
/// is set aside under a dated key first, never deleted (the publisher's
/// rule, 14 Nov). Then the identity reads as absent and onboarding opens, whose
/// first screen offers the restore.
class _RestoreOverGarbledIdentity extends ConsumerWidget {
  const _RestoreOverGarbledIdentity();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton(
          onPressed: () => _confirm(context, ref),
          child: const Text('Restore from words or backup'),
        ),
      );

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this phone?'),
        content: const Text('Porch cannot read the identity stored on this '
            'phone. You can restore it with your 12 recovery words or a '
            'backup file. The unreadable copy is set aside on this phone, '
            'not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Set aside and restore'),
          ),
        ],
      ),
    );
    if (go != true) return;
    final now = DateTime.fromMillisecondsSinceEpoch(
        ref.read(clockProvider)() * 1000,
        isUtc: true);
    try {
      await ref.read(keyStoreProvider).setAsideCorruptEntropy(now);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn’t set the unreadable identity aside. '
              'Nothing was deleted.')));
      return;
    }
    ref.invalidate(sessionProvider);
  }
}
