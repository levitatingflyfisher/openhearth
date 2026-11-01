// W3-data: relay_config — the runtime-configurable relay endpoint.
//
// The relay URL is a compile-time default (bootstrap's porchRelayUrl) that a
// published build can never change. These tests pin the two pieces that make
// it changeable at runtime: the pure "effective URL" resolution (stored value
// wins; empty/invalid → the shipped default) and the SecretStore-backed
// persistence (round-trips through the same abstraction the app secrets use).
import 'package:test/test.dart';

import 'package:porch_app/data/key_store.dart' show InMemorySecretStore;
import 'package:porch_app/data/relay_config.dart';

void main() {
  const fallback = 'https://relay.porch.invalid';

  group('effectiveRelayUrl (resolution)', () {
    test('null stored → the shipped default', () {
      expect(effectiveRelayUrl(stored: null, fallback: fallback).toString(),
          fallback);
    });

    test('empty stored → the shipped default', () {
      expect(effectiveRelayUrl(stored: '', fallback: fallback).toString(),
          fallback);
    });

    test('whitespace-only stored → the shipped default', () {
      expect(effectiveRelayUrl(stored: '   ', fallback: fallback).toString(),
          fallback);
    });

    test('a valid https URL overrides the default', () {
      expect(
          effectiveRelayUrl(stored: 'https://my.relay.example', fallback: fallback)
              .toString(),
          'https://my.relay.example');
    });

    // https only: Android and iOS release builds would fail quietly on
    // http, but Linux and Windows would send relay traffic in clear.
    test('plain http to another machine falls back, in any build', () {
      for (final debug in [true, false]) {
        expect(
            effectiveRelayUrl(
                    stored: 'http://192.168.1.9:8080',
                    fallback: fallback,
                    debugBuild: debug)
                .toString(),
            fallback,
            reason: 'debugBuild: $debug');
      }
    });

    test('a debug build may use plain http to this machine (a local relayd)',
        () {
      for (final local in [
        'http://127.0.0.1:8080',
        'http://localhost:8080',
        'http://[::1]:8080',
      ]) {
        expect(
            effectiveRelayUrl(stored: local, fallback: fallback, debugBuild: true)
                .toString(),
            local);
      }
    });

    test('a release build refuses plain http even to this machine', () {
      for (final local in ['http://127.0.0.1:8080', 'http://localhost:8080']) {
        expect(
            effectiveRelayUrl(
                    stored: local, fallback: fallback, debugBuild: false)
                .toString(),
            fallback,
            reason: local);
      }
    });

    test('a plain http built-in default is refused too: the placeholder '
        'stands in', () {
      expect(
          effectiveRelayUrl(
                  stored: null,
                  fallback: 'http://relay.example',
                  debugBuild: false)
              .toString(),
          'https://relay.porch.invalid');
    });

    test('isAllowedRelayUrl says the same rule', () {
      expect(isAllowedRelayUrl(Uri.parse('https://r.example')), isTrue);
      expect(isAllowedRelayUrl(Uri.parse('http://r.example')), isFalse);
      expect(
          isAllowedRelayUrl(Uri.parse('http://127.0.0.1:1'), debugBuild: true),
          isTrue);
      expect(
          isAllowedRelayUrl(Uri.parse('http://127.0.0.1:1'), debugBuild: false),
          isFalse);
      expect(isAllowedRelayUrl(Uri.parse('https://')), isFalse);
    });

    test('surrounding whitespace is trimmed', () {
      expect(
          effectiveRelayUrl(
                  stored: '  https://my.relay.example  ', fallback: fallback)
              .toString(),
          'https://my.relay.example');
    });

    test('a stored value without a scheme falls back (never bricks)', () {
      expect(
          effectiveRelayUrl(stored: 'my.relay.example', fallback: fallback)
              .toString(),
          fallback);
    });

    test('a non-http(s) scheme falls back', () {
      expect(
          effectiveRelayUrl(stored: 'ftp://my.relay.example', fallback: fallback)
              .toString(),
          fallback);
    });

    test('outright garbage falls back', () {
      expect(effectiveRelayUrl(stored: ':::not a url', fallback: fallback)
          .toString(),
          fallback);
    });
  });

  group('normalizeRelayInput (what we persist)', () {
    test('empty / whitespace → null (clears the override)', () {
      expect(normalizeRelayInput(''), isNull);
      expect(normalizeRelayInput('   '), isNull);
    });

    test('a bare host gets https:// prepended', () {
      expect(normalizeRelayInput('my.relay.example'), 'https://my.relay.example');
    });

    test('an explicit scheme is preserved and trimmed', () {
      expect(normalizeRelayInput('  http://10.0.0.2:9000 '),
          'http://10.0.0.2:9000');
    });
  });

  group('RelayConfigStore (persistence)', () {
    test('write then read round-trips the URL', () async {
      final store = RelayConfigStore(InMemorySecretStore());
      expect(await store.read(), isNull);
      await store.write('https://my.relay.example');
      expect(await store.read(), 'https://my.relay.example');
    });

    test('clear removes the override', () async {
      final store = RelayConfigStore(InMemorySecretStore());
      await store.write('https://my.relay.example');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('RelayEndpoint (the live, mutable holder read at call time)', () {
    test('url can be swapped after construction', () {
      final ep = RelayEndpoint(Uri.parse(fallback));
      expect(ep.url.toString(), fallback);
      ep.url = Uri.parse('https://my.relay.example');
      expect(ep.url.toString(), 'https://my.relay.example');
    });
  });

  group('isPlaceholderRelay (no relay configured)', () {
    test('the shipped default is a placeholder: .invalid never resolves', () {
      expect(isPlaceholderRelay(Uri.parse(fallback)), isTrue);
      expect(isPlaceholderRelay(Uri.parse(defaultRelayUrl)), isTrue,
          reason: 'no relay is deployed, so a plain build ships none');
    });

    test('any .invalid host is a placeholder, whatever the case or port', () {
      expect(isPlaceholderRelay(Uri.parse('http://x.INVALID:8080')), isTrue);
      expect(isPlaceholderRelay(Uri.parse('https://invalid')), isTrue);
    });

    test('a real-looking relay is configured', () {
      expect(isPlaceholderRelay(Uri.parse('https://my.relay.example')), isFalse);
      expect(isPlaceholderRelay(Uri.parse('http://127.0.0.1:8080')), isFalse);
      expect(isPlaceholderRelay(Uri.parse('https://notinvalid.org')), isFalse);
    });
  });
}
