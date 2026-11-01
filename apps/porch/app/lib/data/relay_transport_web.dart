// relay_transport_web — the browser (package:http) relay transport, used only
// by `flutter build web`.
//
// package:http resolves to a BrowserClient here (XHR/fetch under the hood). We
// keep the same one-request/no-retry contract and map failures to
// RelayUnreachable so callers behave identically. Two honest degrades the web
// preview cannot avoid: the browser attaches its own User-Agent and an Origin
// header (so the §1.2 "no fingerprintable headers" property does NOT hold on
// web), and connection timing is the browser's, not ours (connectTimeout is
// ignored). The web-preview banner owns this downgrade.
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'relay_api.dart' show RelayUnreachable;
import 'relay_transport.dart';

/// Web factory selected by api_client.dart's conditional import.
RelayTransport createRelayTransport({
  Duration timeout = const Duration(seconds: 15),
  Duration connectTimeout = const Duration(seconds: 10),
}) =>
    _WebRelayTransport(timeout: timeout);

class _WebRelayTransport implements RelayTransport {
  final Duration timeout;
  final http.Client _client = http.Client();

  _WebRelayTransport({required this.timeout});

  @override
  void close() => _client.close();

  @override
  Future<RawResponse> send(String method, Uri uri, {Uint8List? body}) async {
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.bodyBytes = body;
    }
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const RelayUnreachable('timeout (delivery unknown)');
    } on http.ClientException catch (e) {
      throw RelayUnreachable('http: ${e.message}');
    }
    final Uint8List bytes;
    try {
      bytes = await streamed.stream.toBytes().timeout(timeout);
    } on TimeoutException {
      throw const RelayUnreachable('timeout (delivery unknown)');
    }
    return RawResponse(streamed.statusCode, bytes);
  }
}
