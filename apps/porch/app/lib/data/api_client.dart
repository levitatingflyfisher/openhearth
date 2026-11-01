// HttpRelayApi — the typed HTTP client (BUILD-SPEC §2 api_client.dart).
//
// Deliberately bare:
//   - NO retries, ever. A retried POST whose first attempt actually landed
//     would duplicate state (a second bulletin entry, a second mailbox
//     blob). Retry policy lives in the outbox, which retries only
//     operations the PROTOCOL makes idempotent (presence slot overwrite).
//   - NO identity material on the wire beyond what a call's own signature
//     requires: requests carry Content-Type and nothing else. On native the
//     user-agent is suppressed; on /v1/ch/* there is structurally nothing
//     identifying to send — the methods have no identity parameters (see
//     RelayApi) and the test suite asserts the emitted header set.
//   - Every non-2xx becomes a typed [RelayError]; socket/timeout failures
//     become [RelayUnreachable] with delivery UNKNOWN.
//
// The raw byte transport is the one platform-specific part, behind
// [RelayTransport] (relay_transport.dart): dart:io HttpClient on device,
// package:http BrowserClient on web. Everything below — JSON shaping, the
// no-retry rule, status→error mapping — is platform-free and host-VM tested.
import 'dart:convert';
import 'dart:typed_data';

import '../domain/domain.dart' show b64;
import 'relay_api.dart';
import 'relay_transport.dart';
import 'relay_transport_io.dart'
    if (dart.library.js_interop) 'relay_transport_web.dart';

class HttpRelayApi implements RelayApi {
  /// The fallback endpoint, used when no live override is wired.
  final Uri baseUrl;

  /// Read on every request so a runtime relay-URL change (settings) takes
  /// effect without rebuilding the client. Null ⇒ use [baseUrl] (tests).
  final Uri Function()? _liveBaseUrl;

  final RelayTransport _transport;

  HttpRelayApi({
    required this.baseUrl,
    Uri Function()? liveBaseUrl,
    Duration timeout = const Duration(seconds: 15),
  })  : _liveBaseUrl = liveBaseUrl,
        _transport = createRelayTransport(timeout: timeout);

  void close() => _transport.close();

  // --- invites ---

  @override
  Future<int> createInvite(
      {required String inviteId, required int ttlHours}) async {
    final body = await _send('POST', '/v1/invites',
        jsonBody: {'inviteId': inviteId, 'ttlHours': ttlHours});
    final expiresAt = body?['expiresAt'];
    if (expiresAt is! int) {
      throw const RelayProtocolError('invite create: missing expiresAt');
    }
    return expiresAt;
  }

  @override
  Future<void> joinInvite(
          {required String inviteId, required Uint8List blob}) =>
      _send('POST', '/v1/invites/$inviteId/join', jsonBody: {'blob': b64(blob)});

  @override
  Future<Uint8List> fetchJoin(
      {required String inviteId, required String proof}) async {
    final body = await _send('GET', '/v1/invites/$inviteId/join',
        query: {'proof': proof});
    return decodeBlobField(body ?? const {}, 'blob');
  }

  @override
  Future<void> putGrant(
          {required String inviteId,
          required String proof,
          required Uint8List blob}) =>
      _send('POST', '/v1/invites/$inviteId/grant',
          jsonBody: {'proof': proof, 'blob': b64(blob)});

  @override
  Future<Uint8List> takeGrant(
      {required String inviteId, required String proof}) async {
    final body = await _send('GET', '/v1/invites/$inviteId/grant',
        query: {'proof': proof});
    return decodeBlobField(body ?? const {}, 'blob');
  }

  // --- mailbox ---

  @override
  Future<void> mailboxPost(
          {required String mailboxId, required Uint8List blob}) =>
      _send('POST', '/v1/mailbox/$mailboxId', jsonBody: {'blob': b64(blob)});

  @override
  Future<List<Uint8List>> mailboxDrain(
      {required String mailboxId, required DrainAuth auth}) async {
    final body =
        await _send('POST', '/v1/mailbox/$mailboxId/drain', jsonBody: auth.toJson());
    final blobs = body?['blobs'];
    if (blobs is! List) throw const RelayProtocolError('drain: missing blobs');
    return [
      for (final b in blobs)
        b is String
            ? base64.decode(b)
            : throw const RelayProtocolError('drain: non-base64 blob'),
    ];
  }

  // --- channel plane: capabilities only ---

  @override
  Future<void> presencePost(
          {required String channelId,
          required String slotId,
          required Uint8List blob,
          required int ttlSec}) =>
      _send('POST', '/v1/ch/$channelId/presence',
          jsonBody: {'slotId': slotId, 'blob': b64(blob), 'ttlSec': ttlSec});

  @override
  Future<List<PresenceSlot>> presenceGet(String channelId) async {
    final body = await _send('GET', '/v1/ch/$channelId/presence');
    final slots = body?['slots'];
    if (slots is! List) {
      throw const RelayProtocolError('presence: missing slots');
    }
    return [
      for (final s in slots)
        if (s is Map<String, Object?> &&
            s['slotId'] is String &&
            s['expiresAt'] is int)
          PresenceSlot(
            slotId: s['slotId'] as String,
            blob: decodeBlobField(s, 'blob'),
            expiresAt: s['expiresAt'] as int,
          )
        else
          throw const RelayProtocolError('presence: malformed slot'),
    ];
  }

  @override
  Future<int> bulletinPost(
      {required String channelId,
      required Uint8List blob,
      bool pinned = false,
      int ttlSec = 0,
      String? slotId}) async {
    final body = await _send('POST', '/v1/ch/$channelId/bulletin',
        jsonBody: {
          'slotId': ?slotId,
          'blob': b64(blob),
          'pinned': pinned,
          'ttlSec': ttlSec,
        });
    final seq = body?['seq'];
    if (seq is! int) throw const RelayProtocolError('bulletin: missing seq');
    return seq;
  }

  @override
  Future<List<BulletinEntry>> bulletinGet(String channelId,
      {int afterSeq = 0}) async {
    final body = await _send('GET', '/v1/ch/$channelId/bulletin',
        query: afterSeq > 0 ? {'afterSeq': '$afterSeq'} : null);
    final entries = body?['entries'];
    if (entries is! List) {
      throw const RelayProtocolError('bulletin: missing entries');
    }
    return [
      for (final e in entries)
        if (e is Map<String, Object?> &&
            e['seq'] is int &&
            e['pinned'] is bool)
          BulletinEntry(
            seq: e['seq'] as int,
            blob: decodeBlobField(e, 'blob'),
            pinned: e['pinned'] as bool,
            expiresAt: e['expiresAt'] as int?,
          )
        else
          throw const RelayProtocolError('bulletin: malformed entry'),
    ];
  }

  @override
  Future<bool> healthz() async {
    try {
      await _send('GET', '/v1/healthz');
      return true;
    } on RelayUnreachable {
      rethrow; // offline is not "unhealthy relay" — callers distinguish
    } on RelayError {
      return false;
    }
  }

  // --- the single transport path ---
  //
  // One request, one response, no retries. Headers: Content-Type only (on
  // native; the browser adds its own on web). The raw send is delegated to the
  // platform [RelayTransport]; status→error mapping and JSON decoding are here.

  Future<Map<String, Object?>?> _send(
    String method,
    String path, {
    Map<String, Object?>? jsonBody,
    Map<String, String>? query,
  }) async {
    final base = _liveBaseUrl?.call() ?? baseUrl;
    final uri = base.replace(path: path, queryParameters: query);
    final body =
        jsonBody != null ? utf8.encode(jsonEncode(jsonBody)) : null;
    final response = await _transport.send(method, uri, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw relayErrorForStatus(response.statusCode);
    }
    if (response.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      throw const RelayProtocolError('response is not JSON');
    }
  }
}
