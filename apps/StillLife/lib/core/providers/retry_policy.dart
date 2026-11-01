import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Still Life never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. Here a failure is a read of the household's inventory, a setting
/// in the keychain or a network call the household started. Either way the
/// household sees the error with its Try again and decides when the next
/// attempt goes out; a quiet loop would read the disk again and again, or
/// send requests nobody asked for, and hold a spinner where the error
/// belongs.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// The app's root container. main() builds it (StillLife boots through an
/// UncontrolledProviderScope), and so do the tests that pin what the root
/// decides.
///
/// [noAutoRetry] is set here for every provider, including those from the
/// shared backup packages, which still build against riverpod 2 and so
/// cannot name a retry policy of their own.
ProviderContainer stillLifeContainer({List<Override> overrides = const []}) =>
    ProviderContainer(retry: noAutoRetry, overrides: overrides);
