/// Mantle never retries a failed provider on its own.
///
/// Riverpod 3 retries a provider that fails, up to 10 times, from 200 ms
/// apart. Here a failure is a read of the device's own data: the database,
/// the bundled content or the keychain. A loop against a broken disk helps
/// nobody, and while it runs the screen holds a spinner where the error and
/// its Try again belong. The household sees the error and decides when to
/// try again.
Duration? noAutoRetry(int retryCount, Object error) => null;
