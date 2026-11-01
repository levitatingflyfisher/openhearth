// lib/core/providers/retry_policy.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Sundial never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. Here a failure is a read of the device's own storage: the
/// database or the keychain. A loop against a broken disk helps nobody, and
/// while it runs the screen holds a spinner where the error and its Try
/// again belong. The household sees the error and decides when to try again.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// The app's root scope. main() builds it, and so do the tests that pin
/// what the root decides, so the policy below is tested where it applies.
///
/// [noAutoRetry] is set here for every provider, including those from the
/// shared backup packages, which build against riverpod 2 as well and so
/// cannot name a retry policy of their own.
ProviderScope sundialProviderScope({
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
