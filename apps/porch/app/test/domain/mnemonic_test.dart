// BIP39 mnemonic (BUILD-SPEC §3.1: 12 words = encode(16B entropy) — encoding
// only, not crypto). W1 acceptance: round-trip + determinism.
import 'dart:typed_data';

import 'package:porch_app/domain/mnemonic.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('mnemonic', () {
    test('encodes 16 bytes to exactly 12 wordlist words', () {
      final words = entropyToMnemonic(_bytes(List.filled(16, 0x7f)));
      expect(words, hasLength(12));
      for (final w in words) {
        expect(w, matches(RegExp(r'^[a-z]+$')));
      }
    });

    test('round-trips entropy → words → entropy byte-identically', () {
      final entropy =
          _bytes([for (var i = 0; i < 16; i++) (i * 37 + 5) & 0xff]);
      expect(mnemonicToEntropy(entropyToMnemonic(entropy)), entropy);
    });

    test('same entropy twice → identical words (determinism)', () {
      final entropy = _bytes(List.generate(16, (i) => i));
      expect(entropyToMnemonic(entropy), entropyToMnemonic(entropy));
    });

    // Reference vector from the BIP39 spec test set (trezor vectors):
    // entropy 00000000000000000000000000000000 →
    // "abandon abandon ... about" (checksum word differs from filler).
    test('matches the published BIP39 test vector for zero entropy', () {
      final words = entropyToMnemonic(_bytes(List.filled(16, 0)));
      expect(
        words.join(' '),
        'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about',
      );
    });

    test('matches the published BIP39 test vector for 0x7f entropy', () {
      final words = entropyToMnemonic(_bytes(List.filled(16, 0x7f)));
      expect(
        words.join(' '),
        'legal winner thank year wave sausage worth useful legal '
        'winner thank yellow',
      );
    });

    test('rejects wrong entropy length', () {
      expect(() => entropyToMnemonic(_bytes(List.filled(20, 0))),
          throwsA(isA<MnemonicException>()));
    });

    test('rejects wrong word count', () {
      expect(() => mnemonicToEntropy(['abandon']),
          throwsA(isA<MnemonicException>()));
    });

    test('rejects words not in the list', () {
      final words = entropyToMnemonic(_bytes(List.filled(16, 3)));
      final bad = List.of(words)..[4] = 'notaword';
      expect(
          () => mnemonicToEntropy(bad), throwsA(isA<MnemonicException>()));
    });

    test('rejects a tampered checksum (last word swapped)', () {
      final words = entropyToMnemonic(_bytes(List.filled(16, 3)));
      // 'abandon' as final word will (for this entropy) break the checksum.
      final bad = List.of(words)..[11] = 'abandon';
      expect(
          () => mnemonicToEntropy(bad), throwsA(isA<MnemonicException>()));
    });

    test('accepts case-insensitive, whitespace-tolerant input', () {
      final entropy = _bytes(List.generate(16, (i) => 255 - i));
      final words = entropyToMnemonic(entropy);
      final sloppy =
          words.map((w) => '  ${w.toUpperCase()} ').toList(growable: false);
      expect(mnemonicToEntropy(sloppy), entropy);
    });
  });
}
