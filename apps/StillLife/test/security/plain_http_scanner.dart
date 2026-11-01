// Scans Dart source for "http://" literals that are not on the allowlist.
// See no_remote_plain_http_test.dart for why.

class PlainHttpHit {
  const PlainHttpHit(this.path, this.line, this.text);
  final String path;
  final int line;
  final String text;
}

/// One reviewed exception: a home-network address built from a host and port.
/// Matched by file suffix and pattern, never by line number.
class HomeNetworkAllow {
  const HomeNetworkAllow(this.fileSuffix, this.reason);
  final String fileSuffix;
  final String reason;
}

/// Files that may build `http://$host:$port` (a home-network device has no
/// certificate, so https is not possible there).
const homeNetworkAllowlist = <HomeNetworkAllow>[
  HomeNetworkAllow(
    'core/providers/repository_providers.dart',
    'Ollama home-computer AI base URL from the saved host and port',
  ),
  HomeNetworkAllow(
    'settings/data/llm_connection_tester.dart',
    'tests the Ollama connection the user typed in',
  ),
  HomeNetworkAllow(
    'services/network/ollama_discovery_io.dart',
    'probes home-network hosts for an Ollama server',
  ),
  HomeNetworkAllow(
    'services/network/ollama_discovery_stub.dart',
    'same probe as the io version, for platforms without dart:io',
  ),
  HomeNetworkAllow(
    'services/network/ollama_host.dart',
    'base URL of a discovered Ollama host on the home network',
  ),
  HomeNetworkAllow(
    'services/sync/lan_sync_client.dart',
    'LAN sync talks to another family device on the home network',
  ),
  HomeNetworkAllow(
    'services/sync/lan_sync_server_io.dart',
    'LAN sync server side, home network only',
  ),
];

/// `http://$host:$port` or `http://${...}:${...}`, a host and port that the
/// program fills in at run time.
final _hostPort = RegExp(r'http://\$(\{[^}]*\}|\w+):\$(\{[^}]*\}|\w+)');

/// Loopback only. The character after the name must end the host, so
/// `http://localhost.evil.example` is not allowed.
final _loopback = RegExp(r'^http://(localhost|127\.0\.0\.1)(?![\w.\-@])');

final _httpLiteral = RegExp(r'http://');

/// Returns every disallowed "http://" in [source]. Comment lines are skipped
/// because they are not endpoints.
List<PlainHttpHit> findPlainHttp(String path, String source) {
  final normalized = path.replaceAll('\\', '/');
  final allowedHostPort =
      homeNetworkAllowlist.any((a) => normalized.endsWith(a.fileSuffix));
  final hits = <PlainHttpHit>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    var ok = true;
    for (final m in _httpLiteral.allMatches(line)) {
      final rest = line.substring(m.start);
      if (_loopback.hasMatch(rest)) continue;
      if (allowedHostPort && _hostPort.matchAsPrefix(rest) != null) continue;
      ok = false;
    }
    if (!ok) hits.add(PlainHttpHit(path, i + 1, line));
  }
  return hits;
}
