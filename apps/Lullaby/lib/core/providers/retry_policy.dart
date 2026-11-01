import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Lullaby never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. In Lullaby every failure is a read of the phone's own log. A
/// tired parent must see the failure with its Try again, not a spinner that
/// comes and goes while the disk is read again and again.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// The app's root scope. main() builds it, and so do the tests that pin what
/// the root decides.
///
/// [noAutoRetry] is set here for every provider, including those from the
/// shared backup packages, which still build against riverpod 2 and so
/// cannot name a retry policy of their own.
ProviderScope lullabyProviderScope({
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
