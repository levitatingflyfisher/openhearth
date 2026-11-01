// relay_config — the runtime-configurable relay endpoint.
//
// The shipped default relay URL is a COMPILE-TIME constant ([defaultRelayUrl],
// overridable at build with --dart-define=PORCH_RELAY_URL=...). That is fine
// for a self-built APK but useless for a published binary: the user can never
// point it at a relay they deploy later. This module adds a persisted override
// on top of that default, plus a live holder the HTTP client reads at call
// time so a change takes effect without rebuilding the client.
//
// Platform-free: persistence rides on the SecretStore abstraction
// (key_store.dart), which binds to the platform keystore on device and to the
// browser's storage on web — so this file has zero direct dependency on either
// and stays host-VM testable.
import 'key_store.dart' show SecretStore;

/// The compile-time relay endpoint (was bootstrap's `porchRelayUrl`).
///   flutter build --dart-define=PORCH_RELAY_URL=https://your.relay
/// The default is deliberately non-routable (.invalid TLD): no relay is
/// deployed yet, and a silent default to someone's server would be a lie. The
/// app stays fully functional locally; network ops queue in the outbox.
const defaultRelayUrl = String.fromEnvironment(
  'PORCH_RELAY_URL',
  defaultValue: 'https://relay.porch.invalid',
);

/// True when [url] is a stand-in, not a relay: its host is under the
/// reserved `.invalid` TLD (RFC 2606), which can never resolve. The shipped
/// default is one, so this is how the UI knows no relay is configured and
/// must say so instead of implying that anything is being delivered.
bool isPlaceholderRelay(Uri url) {
  final host = url.host.toLowerCase();
  return host == 'invalid' || host.endsWith('.invalid');
}

/// True in a debug build: neither release (`dart.vm.product`) nor profile.
/// The same test Flutter's kDebugMode makes, without importing Flutter.
const bool _debugBuild = !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');

/// Whether the app may talk to a relay at [url]: https with a host, or,
/// in a debug build only, plain http to this machine (a local relayd).
/// Plain http anywhere else would send relay traffic in clear on Linux and
/// Windows, and fail quietly on Android and iOS release builds.
bool isAllowedRelayUrl(Uri url, {bool debugBuild = _debugBuild}) {
  if (!url.hasScheme || url.host.isEmpty) return false;
  if (url.scheme == 'https') return true;
  return debugBuild && url.scheme == 'http' && _isLoopback(url.host);
}

bool _isLoopback(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h == '::1' ||
      RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(h);
}

/// Stands in when neither the stored URL nor the built-in one is allowed.
const _placeholderRelayUrl = 'https://relay.porch.invalid';

/// Resolve the relay URL the client should actually hit.
///
/// [stored] is the user's persisted override (null before they set one). It
/// wins when [isAllowedRelayUrl] accepts it; anything else (null, empty,
/// whitespace, a schemeless host, plain http, another scheme, garbage)
/// resolves to [fallback], and a [fallback] that is not allowed either
/// resolves to the `.invalid` placeholder. A bad stored value must never
/// brick the app.
Uri effectiveRelayUrl({
  required String? stored,
  required String fallback,
  bool debugBuild = _debugBuild,
}) {
  final trimmed = stored?.trim() ?? '';
  if (trimmed.isNotEmpty) {
    final u = Uri.tryParse(trimmed);
    if (u != null && isAllowedRelayUrl(u, debugBuild: debugBuild)) return u;
  }
  final f = Uri.tryParse(fallback);
  if (f != null && isAllowedRelayUrl(f, debugBuild: debugBuild)) return f;
  return Uri.parse(_placeholderRelayUrl);
}

/// Normalize what the user typed into what we persist (or null to clear the
/// override). Empty/whitespace clears it; a bare host gets `https://`
/// prepended so a paste of "relay.example" behaves as intended.
String? normalizeRelayInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final u = Uri.tryParse(trimmed);
  if (u == null || !u.hasScheme) return 'https://$trimmed';
  return trimmed;
}

/// The user's persisted relay-URL override, behind [SecretStore]. Not a secret
/// as such, but riding the same abstraction means it persists identically on
/// device (keystore) and on web (browser storage) with no extra plumbing.
class RelayConfigStore {
  static const relayUrlKey = 'porch.relayurl.v1';

  final SecretStore _store;
  const RelayConfigStore(this._store);

  /// The stored override, or null if the user never set one.
  Future<String?> read() async {
    final v = await _store.read(relayUrlKey);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> write(String url) => _store.write(relayUrlKey, url);

  Future<void> clear() => _store.delete(relayUrlKey);
}

/// The one live, mutable copy of the effective relay [Uri]. The HTTP client
/// holds a reference and reads [url] on every request, so a settings change
/// takes effect on the next call without rebuilding the client or the session.
class RelayEndpoint {
  Uri url;
  RelayEndpoint(this.url);
}
