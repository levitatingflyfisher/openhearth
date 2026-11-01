/// Reckon never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. In Reckon a failure is a read of the phone's own data (the
/// journal database, the keychain, a bundled asset) or the load of the
/// on-device model. A read that fails once on the phone's own disk fails
/// again, and a quiet loop only puts a spinner where the error belongs. A
/// model load that fails would be loaded again and again. Riverpod 2 never
/// retried, and Reckon keeps that: the person asks again with Try again.
///
/// Every async provider in lib/ names this policy, and so does the app's
/// root scope (`reckonProviderScope` in lib/app/root_overrides.dart), which
/// covers the shared backup packages' providers too.
Duration? noAutoRetry(int retryCount, Object error) => null;
