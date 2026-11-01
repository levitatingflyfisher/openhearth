// Canonical JSON — the signing/encryption input everywhere (BUILD-SPEC §3):
// object keys sorted, no whitespace, integers only.
//
// Determinism contract: two structurally-equal values always produce the same
// bytes, so detached signatures made over `canonicalJsonBytes(payload)` verify
// on every device. Protocol keys are ASCII, where UTF-16 code-unit order
// (String.compareTo) and UTF-8 byte order agree; emitting non-ASCII *keys* is
// rejected to keep that equivalence honest.
//
// Floats are rejected outright: the Porch wire protocol is integer-only
// (unix seconds, epochs, counters) and float canonicalisation is a
// cross-language bug factory we simply refuse to enter.
import 'dart:convert';
import 'dart:typed_data';

/// Canonical JSON string of [value]. Throws [ArgumentError] on doubles,
/// non-string / non-ASCII map keys, or unsupported object types.
String canonicalJson(Object? value) {
  final buf = StringBuffer();
  _write(buf, value);
  return buf.toString();
}

/// UTF-8 bytes of [canonicalJson] — the exact input for signing and AEAD.
Uint8List canonicalJsonBytes(Object? value) =>
    utf8.encode(canonicalJson(value));

/// Lenient decode of untrusted plaintext into a JSON object; null if the
/// bytes are not UTF-8 JSON or not an object. (Decoding accepts any valid
/// JSON — canonical form is only required when ENCODING for signatures.)
Map<String, Object?>? decodeJsonMap(Uint8List bytes) {
  try {
    final v = jsonDecode(utf8.decode(bytes));
    return v is Map<String, Object?> ? v : null;
  } on Object {
    return null;
  }
}

void _write(StringBuffer buf, Object? value) {
  switch (value) {
    case null:
      buf.write('null');
    case bool b:
      buf.write(b ? 'true' : 'false');
    case int i:
      buf.write(i.toString());
    case double _:
      throw ArgumentError(
          'canonicalJson: doubles are not representable on the Porch wire');
    case String s:
      buf.write(jsonEncode(s));
    case List<Object?> list:
      buf.write('[');
      for (var i = 0; i < list.length; i++) {
        if (i > 0) buf.write(',');
        _write(buf, list[i]);
      }
      buf.write(']');
    case Map<Object?, Object?> map:
      final keys = <String>[];
      for (final k in map.keys) {
        if (k is! String) {
          throw ArgumentError('canonicalJson: map keys must be strings');
        }
        for (final unit in k.codeUnits) {
          if (unit > 0x7f) {
            throw ArgumentError(
                'canonicalJson: protocol keys must be ASCII, got "$k"');
          }
        }
        keys.add(k);
      }
      keys.sort();
      buf.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        _write(buf, map[keys[i]]);
      }
      buf.write('}');
    default:
      throw ArgumentError(
          'canonicalJson: unsupported type ${value.runtimeType}');
  }
}
