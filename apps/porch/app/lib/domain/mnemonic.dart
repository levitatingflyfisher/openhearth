// BIP39 mnemonic encoding of the 16-byte identity entropy (BUILD-SPEC §3.1).
//
// This is ENCODING, not crypto: the 12 words are a human-readable spelling of
// the entropy the user must write down. The SHA-256 here contributes 4
// checksum bits so a mistyped word is caught at restore time — no secret
// depends on it (that is why the pure-Dart `crypto` package is acceptable
// here while everything key-bearing goes through libsodium).
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'support/bip39_words.dart';

class MnemonicException implements Exception {
  final String message;
  const MnemonicException(this.message);
  @override
  String toString() => 'MnemonicException: $message';
}

const int _entropyBytes = 16; // 128 bits → 12 words (BIP39 with 4-bit checksum)
const int _wordCount = 12;
const int _checksumBits = 4;

/// Encode 16 bytes of entropy as 12 BIP39 English words.
List<String> entropyToMnemonic(Uint8List entropy) {
  if (entropy.length != _entropyBytes) {
    throw MnemonicException(
        'entropy must be $_entropyBytes bytes, got ${entropy.length}');
  }
  final checksum = sha256.convert(entropy).bytes[0] >> (8 - _checksumBits);
  // 132 bits total: 128 entropy + 4 checksum, split into 12 × 11-bit indices.
  var acc = BigInt.zero;
  for (final b in entropy) {
    acc = (acc << 8) | BigInt.from(b);
  }
  acc = (acc << _checksumBits) | BigInt.from(checksum);
  final words = List<String>.filled(_wordCount, '');
  final mask = BigInt.from(0x7ff);
  for (var i = _wordCount - 1; i >= 0; i--) {
    words[i] = bip39English[(acc & mask).toInt()];
    acc = acc >> 11;
  }
  return words;
}

/// Decode 12 BIP39 words back to the 16 entropy bytes, verifying the
/// checksum. Tolerates case and surrounding whitespace (humans type these).
Uint8List mnemonicToEntropy(List<String> words) {
  if (words.length != _wordCount) {
    throw MnemonicException(
        'expected $_wordCount words, got ${words.length}');
  }
  var acc = BigInt.zero;
  for (final raw in words) {
    final word = raw.trim().toLowerCase();
    final index = _wordIndex[word];
    if (index == null) {
      throw MnemonicException('"$word" is not a BIP39 word');
    }
    acc = (acc << 11) | BigInt.from(index);
  }
  final checksum = (acc & BigInt.from((1 << _checksumBits) - 1)).toInt();
  var bits = acc >> _checksumBits;
  final entropy = Uint8List(_entropyBytes);
  for (var i = _entropyBytes - 1; i >= 0; i--) {
    entropy[i] = (bits & BigInt.from(0xff)).toInt();
    bits = bits >> 8;
  }
  final expected = sha256.convert(entropy).bytes[0] >> (8 - _checksumBits);
  if (checksum != expected) {
    throw MnemonicException('checksum mismatch — a word is wrong');
  }
  return entropy;
}

/// Whether [word] (already trimmed, lower case) is on the BIP39 list.
bool isBip39Word(String word) => _wordIndex.containsKey(word);

final Map<String, int> _wordIndex = {
  for (var i = 0; i < bip39English.length; i++) bip39English[i]: i,
};
