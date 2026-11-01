// relay_transport — the platform seam under HttpRelayApi.
//
// All the RelayApi logic (JSON shaping, the no-retry rule, status→error
// mapping) is platform-free and lives in api_client.dart. The ONLY thing that
// differs between a phone and a browser tab is the raw byte transport:
//   - native (relay_transport_io.dart) keeps the deliberately-bare dart:io
//     HttpClient: userAgent suppressed, Content-Type the only header we set.
//     The §1.2 header-suppression test pins this and runs on the VM, so the
//     native path must stay byte-identical.
//   - web (relay_transport_web.dart) uses package:http's BrowserClient. A
//     browser adds Origin/User-Agent itself and controls connection timing —
//     an unavoidable fingerprint the honest web-preview notice owns.
//
// This core file carries only the shared types; api_client.dart conditionally
// imports the platform factory. Keeping the types here (not in each impl) is
// what makes the two implementations interchangeable.
import 'dart:typed_data';

/// One relay response, reduced to what the caller needs: a status code and the
/// full body bytes. Status→typed-error mapping stays in api_client.dart.
class RawResponse {
  final int statusCode;
  final Uint8List body;
  const RawResponse(this.statusCode, this.body);
}

/// One request, one response, no retries (the outbox owns retry policy). An
/// implementation MUST throw [RelayUnreachable] (relay_api.dart) — never a
/// platform-specific exception — on socket/timeout failure, so delivery reads
/// as UNKNOWN uniformly across platforms.
abstract interface class RelayTransport {
  Future<RawResponse> send(String method, Uri uri, {Uint8List? body});
  void close();
}
