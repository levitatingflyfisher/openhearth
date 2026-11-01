import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/services/backup_stream_cipher.dart';

/// A real HKDF over a fixed test secret, the same parameters the app uses.
FileKeyDeriver deriverFor(int seedByte) => (salt) async {
      final secret = Uint8List.fromList([
        ...List<int>.filled(32, seedByte),
        ...salt,
      ]);
      final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(secret),
        nonce: const <int>[],
        info: 'test'.codeUnits,
      );
      return Uint8List.fromList(await key.extractBytes());
    };

const chunk = BackupStreamCipher.minChunkSize;
const record = chunk + BackupStreamCipher.tagLength;
const header = BackupStreamCipher.headerLength;

Uint8List bytesOf(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + 7) & 0xff));

/// Splits [data] into uneven pieces, the way a file reader delivers them.
Stream<List<int>> piecesOf(List<int> data, {int piece = 700}) async* {
  for (var i = 0; i < data.length; i += piece) {
    yield data.sublist(i, i + piece > data.length ? data.length : i + piece);
  }
}

Future<Uint8List> seal(List<int> plain, {int seed = 1}) async {
  final out = BytesBuilder(copy: false);
  await for (final part in BackupStreamCipher.encrypt(
      piecesOf(plain), deriverFor(seed),
      chunkSize: chunk)) {
    out.add(part);
  }
  return out.toBytes();
}

Future<Uint8List> open(List<int> sealed, {int seed = 1}) async {
  final out = BytesBuilder(copy: false);
  await for (final part
      in BackupStreamCipher.decrypt(piecesOf(sealed, piece: 333), deriverFor(seed))) {
    out.add(part);
  }
  return out.toBytes();
}

void main() {
  group('BackupStreamCipher', () {
    test('round trip over several chunks and a short last one', () async {
      final plain = bytesOf(chunk * 3 + 123);
      final sealed = await seal(plain);
      expect(sealed.length, header + plain.length + 4 * 16);
      expect(await open(sealed), plain);
    });

    test('an empty file seals to a header and one tag, and opens empty',
        () async {
      final sealed = await seal(const []);
      expect(sealed.length, header + 16);
      expect(await open(sealed), isEmpty);
    });

    test('a file of exactly one chunk is one final chunk', () async {
      final plain = bytesOf(chunk);
      final sealed = await seal(plain);
      expect(sealed.length, header + record);
      expect(await open(sealed), plain);
    });

    test('a file of exactly two chunks round-trips', () async {
      final plain = bytesOf(chunk * 2);
      final sealed = await seal(plain);
      expect(sealed.length, header + 2 * record);
      expect(await open(sealed), plain);
    });

    test('the header starts with the OHBS magic and a fresh salt each time',
        () async {
      final a = await seal(bytesOf(10));
      final b = await seal(bytesOf(10));
      expect(BackupStreamCipher.looksEncrypted(a), isTrue);
      expect(a.sublist(12, header), isNot(b.sublist(12, header)));
      expect(a.sublist(header), isNot(b.sublist(header)));
    });

    test('a plain ZIP does not look encrypted', () {
      expect(BackupStreamCipher.looksEncrypted([0x50, 0x4B, 0x03, 0x04]),
          isFalse);
    });

    test('a flipped byte in a chunk fails', () async {
      final sealed = await seal(bytesOf(chunk * 2 + 5));
      sealed[header + record + 10] ^= 0x01;
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('a flipped byte in a tag fails', () async {
      final sealed = await seal(bytesOf(chunk + 5));
      sealed[header + record - 1] ^= 0x80;
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('a changed salt in the header fails', () async {
      final sealed = await seal(bytesOf(chunk + 5));
      sealed[20] ^= 0x01;
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('a changed chunk size in the header fails', () async {
      final sealed = await seal(bytesOf(chunk + 5));
      sealed[10] ^= 0x01; // 1024 -> 1280, still in range
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('a dropped middle chunk fails', () async {
      final sealed = await seal(bytesOf(chunk * 3 + 5));
      final dropped = [
        ...sealed.sublist(0, header + record),
        ...sealed.sublist(header + 2 * record),
      ];
      expect(open(dropped), throwsA(isA<BackupStreamException>()));
    });

    test('two swapped chunks fail', () async {
      final sealed = await seal(bytesOf(chunk * 3 + 5));
      final first = sealed.sublist(header, header + record);
      final second = sealed.sublist(header + record, header + 2 * record);
      final swapped = [
        ...sealed.sublist(0, header),
        ...second,
        ...first,
        ...sealed.sublist(header + 2 * record),
      ];
      expect(open(swapped), throwsA(isA<BackupStreamException>()));
    });

    test('a file cut at a chunk boundary fails', () async {
      final sealed = await seal(bytesOf(chunk * 3 + 5));
      final cut = sealed.sublist(0, header + 2 * record);
      expect(open(cut), throwsA(isA<BackupStreamException>()));
    });

    test('a file cut inside a chunk fails', () async {
      final sealed = await seal(bytesOf(chunk * 3 + 5));
      final cut = sealed.sublist(0, sealed.length - 3);
      expect(open(cut), throwsA(isA<BackupStreamException>()));
    });

    test('a file cut to its header alone fails', () async {
      final sealed = await seal(bytesOf(chunk + 5));
      expect(open(sealed.sublist(0, header)),
          throwsA(isA<BackupStreamException>()));
    });

    test('bytes appended after the final chunk fail', () async {
      final sealed = await seal(bytesOf(chunk + 5));
      expect(open([...sealed, ...bytesOf(40)]),
          throwsA(isA<BackupStreamException>()));
    });

    test('the wrong key fails', () async {
      final sealed = await seal(bytesOf(chunk + 5), seed: 1);
      expect(open(sealed, seed: 2), throwsA(isA<BackupStreamException>()));
    });

    test('a short or foreign header fails', () async {
      expect(open(bytesOf(10)), throwsA(isA<BackupStreamException>()));
      final zip = [0x50, 0x4B, 0x03, 0x04, ...bytesOf(100)];
      expect(open(zip), throwsA(isA<BackupStreamException>()));
    });

    test('an unknown version fails', () async {
      final sealed = await seal(bytesOf(5));
      sealed[4] = 0x02;
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('a chunk size out of range is refused on both sides', () async {
      expect(
          () => BackupStreamCipher.encrypt(
                  piecesOf(bytesOf(5)), deriverFor(1), chunkSize: 10)
              .drain<void>(),
          throwsArgumentError);
      final sealed = await seal(bytesOf(5));
      sealed[8] = 0x7f; // far past 16 MiB
      expect(open(sealed), throwsA(isA<BackupStreamException>()));
    });

    test('portable 64-bit counter encoding matches ByteData.setUint64 byte-for-byte',
        () {
      const testCounters = [
        0,
        1,
        255,
        0x12345678,
        0xFFFFFFFF,
        0x100000000,
        0x00123456789ABCDE,
      ];
      for (final counter in testCounters) {
        final portable = Uint8List(12);
        BackupStreamCipher.writeUint64BigEndian(
            ByteData.sublistView(portable), 4, counter);

        final reference = Uint8List(12);
        ByteData.sublistView(reference).setUint64(4, counter, Endian.big);

        expect(portable, equals(reference),
            reason: 'counter 0x${counter.toRadixString(16)} byte mismatch');
      }
    });
  });
}
