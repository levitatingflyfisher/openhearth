// W3-data: typed relay HTTP client (BUILD-SPEC §2 api_client.dart, §4).
//
// Black-box: every test drives HttpRelayApi against a real dart:io
// HttpServer that records exactly what arrived on the wire — paths, bodies,
// headers — and answers with canned relay responses. This pins the client to
// the Go relay's actual JSON conventions (std base64 blobs, base64url ids)
// and proves the two structural rules:
//   1. NO identity material ever rides a /v1/ch/* request (§1.2), and
//   2. the client NEVER retries — a retried bulletin post would duplicate
//      state; retry policy belongs to the outbox, which knows which ops are
//      idempotent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/api_client.dart';
import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/domain/domain.dart';

import '../domain/support/test_sodium.dart';

/// One recorded request as the server saw it.
class RecordedRequest {
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, List<String>> headers;
  final String body;
  RecordedRequest(this.method, this.path, this.query, this.headers, this.body);
}

class CannedResponse {
  final int status;
  final Object? jsonBody;
  CannedResponse(this.status, [this.jsonBody]);
}

class TestRelayServer {
  late final HttpServer _server;
  final requests = <RecordedRequest>[];

  /// Responses consumed in order; when empty, answers 200 {}.
  final responses = <CannedResponse>[];

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final headers = <String, List<String>>{};
      req.headers.forEach((k, v) => headers[k.toLowerCase()] = v);
      requests.add(RecordedRequest(req.method, req.uri.path,
          req.uri.queryParameters, headers, body));
      final canned =
          responses.isEmpty ? CannedResponse(200, {}) : responses.removeAt(0);
      req.response.statusCode = canned.status;
      if (canned.jsonBody != null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(canned.jsonBody));
      }
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  // The fleet's test/flutter_test_config.dart initializes the widget test
  // binding for every file, and that binding swaps in HttpOverrides that
  // answer every request with 400 without touching the network. These
  // tests talk to a real loopback HttpServer.
  setUpAll(() => HttpOverrides.global = null);

  late TestRelayServer server;
  late HttpRelayApi api;

  setUp(() async {
    server = TestRelayServer();
    await server.start();
    api = HttpRelayApi(baseUrl: server.baseUrl);
  });

  tearDown(() async {
    api.close();
    await server.stop();
  });

  Uint8List blobOf(String s) => Uint8List.fromList(utf8.encode(s));

  group('invite endpoints (§4 rows 1–5)', () {
    test('createInvite posts {inviteId, ttlHours} and returns expiresAt',
        () async {
      server.responses.add(CannedResponse(201, {'expiresAt': 1234567890}));
      final expiresAt = await api.createInvite(
          inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', ttlHours: 72);
      expect(expiresAt, 1234567890);
      final r = server.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/v1/invites');
      expect(jsonDecode(r.body),
          {'inviteId': 'aaaaaaaaaaaaaaaaaaaaaa', 'ttlHours': 72});
    });

    test('createInvite 409 → RelayConflict', () async {
      server.responses.add(CannedResponse(409));
      await expectLater(
          api.createInvite(inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', ttlHours: 1),
          throwsA(isA<RelayConflict>()));
    });

    test('joinInvite posts std-base64 blob, 204 completes', () async {
      server.responses.add(CannedResponse(204));
      await api.joinInvite(
          inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', blob: blobOf('intro'));
      final r = server.requests.single;
      expect(r.path, '/v1/invites/aaaaaaaaaaaaaaaaaaaaaa/join');
      expect(jsonDecode(r.body), {'blob': base64.encode(utf8.encode('intro'))});
    });

    test('joinInvite 410 (already consumed) → RelayGone', () async {
      server.responses.add(CannedResponse(410));
      await expectLater(
          api.joinInvite(
              inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', blob: blobOf('x')),
          throwsA(isA<RelayGone>()));
    });

    test('fetchJoin sends proof as query param, decodes blob', () async {
      server.responses
          .add(CannedResponse(200, {'blob': base64.encode([1, 2, 3])}));
      final blob = await api.fetchJoin(
          inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', proof: 'p' * 43);
      expect(blob, [1, 2, 3]);
      final r = server.requests.single;
      expect(r.method, 'GET');
      expect(r.path, '/v1/invites/aaaaaaaaaaaaaaaaaaaaaa/join');
      expect(r.query, {'proof': 'p' * 43});
    });

    test('putGrant posts {proof, blob}', () async {
      server.responses.add(CannedResponse(204));
      await api.putGrant(
          inviteId: 'aaaaaaaaaaaaaaaaaaaaaa',
          proof: 'p' * 43,
          blob: blobOf('grant'));
      expect(jsonDecode(server.requests.single.body),
          {'proof': 'p' * 43, 'blob': base64.encode(utf8.encode('grant'))});
    });

    test('takeGrant GETs with proof and decodes blob; 404 → RelayNotFound',
        () async {
      server.responses
          .add(CannedResponse(200, {'blob': base64.encode([9])}));
      final blob = await api.takeGrant(
          inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', proof: 'g' * 43);
      expect(blob, [9]);
      expect(server.requests.single.path,
          '/v1/invites/aaaaaaaaaaaaaaaaaaaaaa/grant');

      server.responses.add(CannedResponse(404));
      await expectLater(
          api.takeGrant(inviteId: 'aaaaaaaaaaaaaaaaaaaaaa', proof: 'g' * 43),
          throwsA(isA<RelayNotFound>()));
    });
  });

  group('mailbox endpoints (§4 rows 6–7)', () {
    test('mailboxPost is anonymous, 429 → RelayRateLimited', () async {
      server.responses.add(CannedResponse(204));
      await api.mailboxPost(mailboxId: 'm' * 43, blob: blobOf('sealed'));
      final r = server.requests.single;
      expect(r.path, '/v1/mailbox/${'m' * 43}');
      expect(jsonDecode(r.body), {'blob': base64.encode(utf8.encode('sealed'))});

      server.responses.add(CannedResponse(429));
      await expectLater(api.mailboxPost(mailboxId: 'm' * 43, blob: blobOf('x')),
          throwsA(isA<RelayRateLimited>()));
    });

    test('mailboxDrain posts the signed auth body and decodes blobs',
        () async {
      final sodium = await loadTestSodium();
      final identity =
          PorchIdentity.fromEntropy(sodium, Uint8List.fromList(List.filled(16, 7)));
      final auth = buildDrainAuth(sodium,
          sign: identity.sign, mailboxId: identity.mailboxId, ts: 1700000000);

      server.responses.add(CannedResponse(200, {
        'blobs': [base64.encode([1]), base64.encode([2, 2])],
      }));
      final blobs =
          await api.mailboxDrain(mailboxId: identity.mailboxId, auth: auth);
      expect(blobs, [
        [1],
        [2, 2]
      ]);

      final r = server.requests.single;
      expect(r.path, '/v1/mailbox/${identity.mailboxId}/drain');
      final body = jsonDecode(r.body) as Map<String, Object?>;
      expect(body.keys.toSet(), {'pubkey', 'ts', 'sig'});
      expect(body['ts'], 1700000000);
      // The signature must verify over the relay's exact message format:
      // "porch-drain|{mailboxId}|{ts}" (§4 row 7).
      final ok = sodium.crypto.sign.verifyDetached(
        message: Uint8List.fromList(
            utf8.encode('porch-drain|${identity.mailboxId}|1700000000')),
        signature: b64decode(body['sig'] as String),
        publicKey: b64decode(body['pubkey'] as String),
      );
      expect(ok, isTrue);
      expect(b64decode(body['pubkey'] as String), identity.sign.publicKey);
    });

    test('drain 401 → RelayUnauthorized', () async {
      final sodium = await loadTestSodium();
      final identity =
          PorchIdentity.fromEntropy(sodium, Uint8List.fromList(List.filled(16, 8)));
      server.responses.add(CannedResponse(401));
      await expectLater(
          api.mailboxDrain(
              mailboxId: identity.mailboxId,
              auth: buildDrainAuth(sodium,
                  sign: identity.sign,
                  mailboxId: identity.mailboxId,
                  ts: 1)),
          throwsA(isA<RelayUnauthorized>()));
    });
  });

  group('channel plane (§4 rows 8–11)', () {
    test('presencePost sends {slotId, blob, ttlSec}', () async {
      server.responses.add(CannedResponse(204));
      await api.presencePost(
          channelId: 'c' * 43,
          slotId: 's' * 22,
          blob: blobOf('env'),
          ttlSec: 3600);
      final r = server.requests.single;
      expect(r.path, '/v1/ch/${'c' * 43}/presence');
      expect(jsonDecode(r.body), {
        'slotId': 's' * 22,
        'blob': base64.encode(utf8.encode('env')),
        'ttlSec': 3600,
      });
    });

    test('presenceGet decodes slots', () async {
      server.responses.add(CannedResponse(200, {
        'slots': [
          {'slotId': 's' * 22, 'blob': base64.encode([5]), 'expiresAt': 99},
        ]
      }));
      final slots = await api.presenceGet('c' * 43);
      expect(slots, hasLength(1));
      expect(slots.single.slotId, 's' * 22);
      expect(slots.single.blob, [5]);
      expect(slots.single.expiresAt, 99);
    });

    test('bulletinPost returns the server seq; unpinned sends ttlSec 0',
        () async {
      server.responses.add(CannedResponse(200, {'seq': 17}));
      final seq =
          await api.bulletinPost(channelId: 'c' * 43, blob: blobOf('op'));
      expect(seq, 17);
      expect(jsonDecode(server.requests.single.body), {
        'blob': base64.encode(utf8.encode('op')),
        'pinned': false,
        'ttlSec': 0,
      });
    });

    test('bulletinPost names the writer by its slot id when given', () async {
      server.responses.add(CannedResponse(200, {'seq': 2}));
      await api.bulletinPost(
          channelId: 'c' * 43, blob: blobOf('op'), slotId: 's' * 22);
      expect(jsonDecode(server.requests.single.body), {
        'slotId': 's' * 22,
        'blob': base64.encode(utf8.encode('op')),
        'pinned': false,
        'ttlSec': 0,
      });
    });

    test('bulletinPost pinned carries its own TTL', () async {
      server.responses.add(CannedResponse(200, {'seq': 1}));
      await api.bulletinPost(
          channelId: 'c' * 43, blob: blobOf('escrow'), pinned: true, ttlSec: 7200);
      expect(jsonDecode(server.requests.single.body), {
        'blob': base64.encode(utf8.encode('escrow')),
        'pinned': true,
        'ttlSec': 7200,
      });
    });

    test('bulletinGet passes afterSeq and decodes entries', () async {
      server.responses.add(CannedResponse(200, {
        'entries': [
          {'seq': 3, 'blob': base64.encode([1]), 'pinned': false},
          {'seq': 4, 'blob': base64.encode([2]), 'pinned': true, 'expiresAt': 60},
        ]
      }));
      final entries = await api.bulletinGet('c' * 43, afterSeq: 2);
      expect(server.requests.single.query, {'afterSeq': '2'});
      expect(entries, hasLength(2));
      expect(entries[0].seq, 3);
      expect(entries[0].pinned, isFalse);
      expect(entries[0].expiresAt, isNull);
      expect(entries[1].seq, 4);
      expect(entries[1].pinned, isTrue);
      expect(entries[1].expiresAt, 60);
    });

    test('STRUCTURAL: /v1/ch/* requests carry no identity material (§1.2)',
        () async {
      server.responses.add(CannedResponse(204));
      server.responses.add(CannedResponse(200, {'slots': []}));
      server.responses.add(CannedResponse(200, {'seq': 1}));
      server.responses.add(CannedResponse(200, {'entries': []}));
      await api.presencePost(
          channelId: 'c' * 43, slotId: 's' * 22, blob: blobOf('e'), ttlSec: 60);
      await api.presenceGet('c' * 43);
      await api.bulletinPost(channelId: 'c' * 43, blob: blobOf('e'));
      await api.bulletinGet('c' * 43);

      const allowed = {
        // Transport-mechanical headers only. NOTHING identity-shaped:
        // no cookie, no authorization, no user-agent, no custom x-*.
        'host', 'content-type', 'content-length', 'accept-encoding',
        'connection', 'transfer-encoding',
      };
      expect(server.requests, hasLength(4));
      for (final r in server.requests) {
        expect(r.path, startsWith('/v1/ch/'));
        for (final name in r.headers.keys) {
          expect(allowed, contains(name),
              reason: 'identity-capable header "$name" on channel plane');
        }
      }
    });
  });

  group('typed errors and the no-retry rule', () {
    test('500 → RelayServerError after EXACTLY one request (no retry)',
        () async {
      server.responses.add(CannedResponse(500));
      await expectLater(
          api.bulletinPost(channelId: 'c' * 43, blob: blobOf('once')),
          throwsA(isA<RelayServerError>()));
      expect(server.requests, hasLength(1),
          reason: 'a retried bulletin post would duplicate state');
    });

    test('400 → RelayBadRequest, 413 → RelayTooLarge', () async {
      server.responses.add(CannedResponse(400));
      await expectLater(api.presenceGet('c' * 43),
          throwsA(isA<RelayBadRequest>()));
      server.responses.add(CannedResponse(413));
      await expectLater(
          api.mailboxPost(mailboxId: 'm' * 43, blob: blobOf('big')),
          throwsA(isA<RelayTooLarge>()));
    });

    test('connection refused → RelayUnreachable', () async {
      final dead = HttpRelayApi(
          baseUrl: Uri.parse('http://127.0.0.1:1')); // reserved port, closed
      addTearDown(dead.close);
      await expectLater(
          dead.presenceGet('c' * 43), throwsA(isA<RelayUnreachable>()));
    });

    test('malformed response JSON → RelayProtocolError', () async {
      server.responses.add(CannedResponse(200, {'unexpected': true}));
      await expectLater(
          api.presenceGet('c' * 43), throwsA(isA<RelayProtocolError>()));
    });

    test('healthz true on 200, false is impossible without an error',
        () async {
      server.responses.add(CannedResponse(200));
      expect(await api.healthz(), isTrue);
      expect(server.requests.single.path, '/v1/healthz');
      server.responses.add(CannedResponse(500));
      expect(await api.healthz(), isFalse);
    });
  });

  // The production wiring (bootstrap) always passes liveBaseUrl, so EVERY real
  // request resolves its host through this supplier — the mechanism that makes
  // the runtime relay-URL setting load-bearing. Pin it directly.
  group('liveBaseUrl (runtime relay endpoint)', () {
    test('a request targets liveBaseUrl, not the constructor baseUrl',
        () async {
      // baseUrl is a dead port; only the live supplier points at the server.
      final client = HttpRelayApi(
        baseUrl: Uri.parse('http://127.0.0.1:1'),
        liveBaseUrl: () => server.baseUrl,
      );
      addTearDown(client.close);
      server.responses.add(CannedResponse(200));
      expect(await client.healthz(), isTrue);
      expect(server.requests.single.path, '/v1/healthz',
          reason: 'the call reached the live endpoint, not the dead baseUrl');
    });

    test('the supplier is re-read on every call (a change takes effect live)',
        () async {
      var live = Uri.parse('http://127.0.0.1:1'); // unreachable at first
      final client = HttpRelayApi(
        baseUrl: Uri.parse('http://127.0.0.1:1'),
        liveBaseUrl: () => live,
      );
      addTearDown(client.close);
      await expectLater(client.healthz(), throwsA(isA<RelayUnreachable>()),
          reason: 'the dead endpoint is unreachable; no request is served');
      expect(server.requests, isEmpty);

      // Point the SAME client at the live server; no rebuild.
      live = server.baseUrl;
      server.responses.add(CannedResponse(200));
      expect(await client.healthz(), isTrue);
      expect(server.requests.single.path, '/v1/healthz');
    });
  });
}
