// Byte/encoding helpers shared across the domain.
//
// Wire conventions (must match the Go relay — see W1-relay HONEST-STATUS):
//   ids (inviteId, mailboxId, channelId, slotId, proofs) → base64url, NO padding
//   blob/pubkey/sig JSON fields                          → standard base64
import 'dart:convert';
import 'dart:typed_data';

/// base64url without padding — the encoding for every capability id.
String b64urlNoPad(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64urlNoPadDecode(String s) {
  final padded = s.padRight(s.length + ((4 - s.length % 4) % 4), '=');
  return base64Url.decode(padded);
}

/// Standard base64 for blob-ish JSON fields.
String b64(List<int> bytes) => base64.encode(bytes);

Uint8List b64decode(String s) => base64.decode(s);

/// 8-byte little-endian encoding (envelope AD epoch binding, §3.3).
Uint8List le64(int value) {
  final out = Uint8List(8);
  ByteData.view(out.buffer).setUint64(0, value, Endian.little);
  return out;
}

/// Content equality for byte arrays (NOT constant-time; never use to compare
/// secrets — libsodium does its own constant-time MAC checks).
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Concatenate byte segments.
Uint8List concatBytes(List<List<int>> segments) {
  final total = segments.fold<int>(0, (n, s) => n + s.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final s in segments) {
    out.setAll(offset, s);
    offset += s.length;
  }
  return out;
}
