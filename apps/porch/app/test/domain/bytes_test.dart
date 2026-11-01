// Byte/encoding helpers: ids are base64url-no-padding on the wire
// (W1-relay HONEST-STATUS pins this convention); epoch AD uses le64.
import 'dart:typed_data';

import 'package:porch_app/domain/support/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('base64url no padding', () {
    test('round-trips arbitrary bytes', () {
      final data = Uint8List.fromList(List.generate(37, (i) => (i * 11) & 0xff));
      final s = b64urlNoPad(data);
      expect(s, isNot(contains('=')));
      expect(s, isNot(contains('+')));
      expect(s, isNot(contains('/')));
      expect(b64urlNoPadDecode(s), data);
    });

    test('handles every length mod 4', () {
      for (final n in [0, 1, 2, 3, 4, 5, 31, 32, 33]) {
        final data = Uint8List.fromList(List.generate(n, (i) => i));
        expect(b64urlNoPadDecode(b64urlNoPad(data)), data,
            reason: 'length $n');
      }
    });
  });

  group('le64', () {
    test('encodes little-endian 8 bytes', () {
      expect(le64(1), [1, 0, 0, 0, 0, 0, 0, 0]);
      expect(le64(0x0102030405060708),
          [8, 7, 6, 5, 4, 3, 2, 1]);
    });
  });

  group('bytesEqual', () {
    test('compares content not identity', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3]);
      final c = Uint8List.fromList([1, 2, 4]);
      expect(bytesEqual(a, b), isTrue);
      expect(bytesEqual(a, c), isFalse);
      expect(bytesEqual(a, Uint8List.fromList([1, 2])), isFalse);
    });
  });
}
