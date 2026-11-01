// relay_transport_io — the native (dart:io) relay transport.
//
// Byte-identical to the original HttpRelayApi._send: a bare HttpClient with
// userAgent suppressed and connectionTimeout set, Content-Type the only header
// we add (and only on bodied requests), and every phase wrapped in the same
// timeout. socket/timeout/http failures become RelayUnreachable. The §1.2
// header-suppression test asserts the emitted header set against this path.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'relay_api.dart' show RelayUnreachable;
import 'relay_transport.dart';

/// Native factory selected by api_client.dart's conditional import.
RelayTransport createRelayTransport({
  Duration timeout = const Duration(seconds: 15),
  Duration connectTimeout = const Duration(seconds: 10),
}) =>
    _IoRelayTransport(timeout: timeout, connectTimeout: connectTimeout);

class _IoRelayTransport implements RelayTransport {
  final Duration timeout;
  final HttpClient _client;

  _IoRelayTransport({required this.timeout, required Duration connectTimeout})
      : _client = HttpClient()
          ..userAgent = null // nothing fingerprintable beyond TLS itself
          ..connectionTimeout = connectTimeout;

  @override
  void close() => _client.close(force: true);

  @override
  Future<RawResponse> send(String method, Uri uri, {Uint8List? body}) async {
    final HttpClientResponse response;
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        request.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        request.add(body);
      }
      response = await request.close().timeout(timeout);
    } on TimeoutException {
      throw const RelayUnreachable('timeout (delivery unknown)');
    } on SocketException catch (e) {
      throw RelayUnreachable('socket: ${e.message}');
    } on HttpException catch (e) {
      throw RelayUnreachable('http: ${e.message}');
    }
    final bytes = await response
        .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk))
        .timeout(timeout)
        .then((b) => b.takeBytes());
    return RawResponse(response.statusCode, bytes);
  }
}
