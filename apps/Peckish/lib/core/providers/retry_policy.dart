// lib/core/providers/retry_policy.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Peckish never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. Here a failure is a read of the phone's own data: the database,
/// the bundled food spine, the keychain or the saved AI settings. A read
/// that fails once on the phone's own disk fails again, and a quiet loop
/// only hides the failure behind a reload. Riverpod 2 never retried, and
/// Peckish keeps that.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// The app's root scope. main() builds it, and so does the test that pins
/// what the root decides, so the policy is tested where it applies.
///
/// [noAutoRetry] is set here for every provider, including those from the
/// shared backup packages, which build against riverpod 2 as well and so
/// cannot name a retry policy of their own.
ProviderScope peckishProviderScope({
  required List<Override> overrides,
  required Widget child,
  Key? key,
}) =>
    ProviderScope(
      key: key,
      retry: noAutoRetry,
      overrides: overrides,
      child: child,
    );
