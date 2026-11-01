// Loads the host's real libsodium for domain tests (BUILD-SPEC §1.5: the
// `sodium` package is Flutter-free, so domain tests run on the Dart VM
// against the host library — no emulator, no plugin registry).
//
// Override the library path with PORCH_LIBSODIUM=/path/to/libsodium.so
// if the host puts it somewhere unusual.
import 'dart:ffi';
import 'dart:io';

import 'package:sodium/sodium_sumo.dart';

Future<SodiumSumo>? _loading;

/// Memoized — for plain `test()` bodies (real async zone). Do NOT use from
/// `testWidgets`: a future completed in one FakeAsync zone schedules its
/// listeners on THAT zone, deadlocking the next test's await. Widget tests
/// use [loadTestSodiumFresh] instead.
Future<SodiumSumo> loadTestSodium() =>
    _loading ??= _load();

/// Un-memoized: creates the future in the CALLER's zone, so `testWidgets`
/// bodies (each in their own FakeAsync zone) can await it safely.
/// libsodium's sodium_init is idempotent; re-init costs milliseconds.
Future<SodiumSumo> loadTestSodiumFresh() => _load();

Future<SodiumSumo> _load() async {
  final override = Platform.environment['PORCH_LIBSODIUM'];
  final candidates = <String>[
    ?override,
    'libsodium.so.26',
    'libsodium.so.23',
    'libsodium.so',
    '/usr/lib64/libsodium.so.26',
    '/usr/lib/x86_64-linux-gnu/libsodium.so.23',
    '/opt/homebrew/lib/libsodium.dylib',
  ];
  Object? lastError;
  for (final path in candidates) {
    try {
      return await SodiumSumoInit.init(() => DynamicLibrary.open(path));
    } on Object catch (e) {
      lastError = e;
    }
  }
  throw StateError(
    'No host libsodium found (tried $candidates). '
    'Install libsodium or set PORCH_LIBSODIUM. Last error: $lastError',
  );
}
