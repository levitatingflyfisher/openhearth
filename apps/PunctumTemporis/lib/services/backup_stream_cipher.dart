import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when an encrypted backup stream is not one we wrote, was cut
/// short, was changed, or was sealed under another key. The restore must
/// stop and keep nothing it decrypted so far.
class BackupStreamException implements Exception {
  const BackupStreamException(this.message);
  final String message;
  @override
  String toString() => 'BackupStreamException: $message';
}

/// Derives the 32-byte key for one file from that file's random salt.
/// The app routes this through `KeyDerivation.deriveKey` in
/// `sanctuary_auth_core`, so HKDF is never written twice.
typedef FileKeyDeriver = Future<Uint8List> Function(Uint8List salt);

/// Chunked ChaCha20-Poly1305 over a stream of any length, in fixed memory.
///
/// A PunctumTemporis backup holds years of video, far past the 10 MB the
/// shared OHBK v2 envelope accepts and far past what a phone can hold in
/// one buffer. So the file is cut into fixed chunks, and each chunk is
/// sealed on its own. Only one chunk is in memory at a time.
///
/// Wire format, version 1 (OHBS = OpenHearth Backup Stream):
/// ```
/// header, 44 bytes:
///   [4]  magic "OHBS"
///   [1]  version 0x01
///   [1]  cipher suite 0x01 = ChaCha20-Poly1305 IETF
///   [2]  reserved, zero
///   [4]  chunk size, big-endian uint32, plaintext bytes per full chunk
///   [32] random salt, new for every file
/// then chunks, in order:
///   [n]  ciphertext (n = chunk size for every chunk but the last;
///        0 to chunk size for the last)
///   [16] Poly1305 tag
/// ```
/// The file key is derived from the salt by the caller ([FileKeyDeriver]),
/// so two files never share a key, and the nonce can safely be the chunk
/// index: 4 zero bytes then the index as a big-endian uint64.
///
/// Each chunk's AAD is `header ‖ index (uint64 BE) ‖ final flag (1 byte)`.
/// The index stops reordering and dropping, the flag stops cutting the
/// file short (the new last chunk was sealed as not final), and the header
/// stops a changed chunk size or salt. An empty input is one final chunk
/// of no bytes, so even an empty file carries a tag.
abstract final class BackupStreamCipher {
  static const magic = <int>[0x4F, 0x48, 0x42, 0x53]; // "OHBS"
  static const version = 0x01;
  static const suiteChaCha20Poly1305 = 0x01;
  static const headerLength = 44;
  static const saltLength = 32;
  static const tagLength = 16;

  /// 1 MiB: big enough that the per-chunk cost is lost in the noise, small
  /// enough that a phone never notices the buffer.
  static const defaultChunkSize = 1024 * 1024;
  static const minChunkSize = 1024;
  static const maxChunkSize = 16 * 1024 * 1024;

  static final _aead = Chacha20.poly1305Aead();

  /// Whether [prefix] starts with the OHBS magic. Lets restore tell an
  /// encrypted backup from a plain ZIP by its first bytes.
  static bool looksEncrypted(List<int> prefix) {
    if (prefix.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (prefix[i] != magic[i]) return false;
    }
    return true;
  }

  /// Seals [input] and yields the header and then each sealed chunk.
  static Stream<List<int>> encrypt(
    Stream<List<int>> input,
    FileKeyDeriver deriveKey, {
    int chunkSize = defaultChunkSize,
    Uint8List? salt,
  }) async* {
    _checkChunkSize(chunkSize);
    final fileSalt = salt ?? _randomSalt();
    if (fileSalt.length != saltLength) {
      throw ArgumentError('Salt must be $saltLength bytes');
    }
    final header = _buildHeader(chunkSize, fileSalt);
    final key = SecretKey(await deriveKey(fileSalt));
    yield header;

    // One full chunk is held back until more input arrives, because only
    // then do we know it is not the last one.
    final buffer = _ChunkBuffer(chunkSize);
    Uint8List? pending;
    var index = 0;
    await for (final piece in input) {
      var offset = 0;
      while (offset < piece.length) {
        offset += buffer.fill(piece, offset);
        if (buffer.isFull) {
          if (pending != null) {
            yield await _seal(pending, key, header, index++, last: false);
          }
          pending = buffer.take();
        }
      }
    }
    if (buffer.length > 0) {
      if (pending != null) {
        yield await _seal(pending, key, header, index++, last: false);
      }
      pending = buffer.take();
    }
    yield await _seal(pending ?? Uint8List(0), key, header, index, last: true);
  }

  /// Opens a stream written by [encrypt] and yields the plaintext, one
  /// verified chunk at a time.
  ///
  /// Throws [BackupStreamException] on a foreign header, a wrong key, a
  /// changed, dropped, reordered or cut-off chunk. Bytes already yielded
  /// were genuine, but the file as a whole is only proven when the stream
  /// ends without an error, so the caller writes to a temporary file and
  /// keeps it only then.
  static Stream<List<int>> decrypt(
    Stream<List<int>> input,
    FileKeyDeriver deriveKey,
  ) async* {
    final headerBuf = _ChunkBuffer(headerLength);
    Uint8List? header;
    SecretKey? key;
    _ChunkBuffer? buffer;
    var record = 0;
    var index = 0;

    await for (final piece in input) {
      var offset = 0;
      if (header == null) {
        offset += headerBuf.fill(piece, offset);
        if (!headerBuf.isFull) continue;
        header = headerBuf.take();
        record = _parseHeader(header) + tagLength;
        key = SecretKey(
            await deriveKey(Uint8List.sublistView(header, 12, headerLength)));
        buffer = _ChunkBuffer(record);
      }
      while (offset < piece.length) {
        // A full record is opened as not final only once at least one more
        // byte is known to follow it; otherwise it may be the last.
        if (buffer!.isFull) {
          yield await _open(buffer.take(), key!, header, index++, last: false);
        }
        offset += buffer.fill(piece, offset);
      }
    }

    if (header == null) {
      throw const BackupStreamException('The file is too short to be a backup');
    }
    final last = buffer!.take();
    if (last.length < tagLength) {
      throw const BackupStreamException('The backup was cut short');
    }
    yield await _open(last, key!, header, index, last: true);
  }

  static Future<Uint8List> _seal(
    Uint8List plain,
    SecretKey key,
    Uint8List header,
    int index, {
    required bool last,
  }) async {
    final box = await _aead.encrypt(
      plain,
      secretKey: key,
      nonce: _nonce(index),
      aad: _aad(header, index, last),
    );
    final out = Uint8List(plain.length + tagLength);
    out.setRange(0, plain.length, box.cipherText);
    out.setRange(plain.length, out.length, box.mac.bytes);
    return out;
  }

  static Future<List<int>> _open(
    Uint8List sealed,
    SecretKey key,
    Uint8List header,
    int index, {
    required bool last,
  }) async {
    final split = sealed.length - tagLength;
    final box = SecretBox(
      Uint8List.sublistView(sealed, 0, split),
      nonce: _nonce(index),
      mac: Mac(Uint8List.sublistView(sealed, split)),
    );
    try {
      return await _aead.decrypt(
        box,
        secretKey: key,
        aad: _aad(header, index, last),
      );
    } on SecretBoxAuthenticationError {
      throw BackupStreamException(
          'Chunk $index did not verify: wrong recovery words, or the file '
          'was changed or cut short');
    }
  }

  static Uint8List _buildHeader(int chunkSize, Uint8List salt) {
    final header = Uint8List(headerLength);
    header.setRange(0, 4, magic);
    header[4] = version;
    header[5] = suiteChaCha20Poly1305;
    ByteData.sublistView(header).setUint32(8, chunkSize);
    header.setRange(12, headerLength, salt);
    return header;
  }

  /// Returns the chunk size, or throws on anything we did not write.
  static int _parseHeader(Uint8List header) {
    if (!looksEncrypted(header)) {
      throw const BackupStreamException('Not an encrypted backup');
    }
    if (header[4] != version) {
      throw BackupStreamException('Unsupported backup version ${header[4]}');
    }
    if (header[5] != suiteChaCha20Poly1305) {
      throw BackupStreamException('Unsupported cipher suite ${header[5]}');
    }
    if (header[6] != 0 || header[7] != 0) {
      throw const BackupStreamException('Reserved header bytes are not zero');
    }
    final chunkSize = ByteData.sublistView(header).getUint32(8);
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw BackupStreamException('Chunk size $chunkSize is out of range');
    }
    return chunkSize;
  }

  /// Writes [value] as an unsigned 64-bit big-endian integer using two 32-bit
  /// writes so dart2js (Web) never throws `UnsupportedError` on `setUint64`.
  static void writeUint64BigEndian(ByteData data, int offset, int value) {
    final hi = value ~/ 0x100000000;
    final lo = value & 0xFFFFFFFF;
    data.setUint32(offset, hi, Endian.big);
    data.setUint32(offset + 4, lo, Endian.big);
  }

  static List<int> _nonce(int index) {
    final nonce = Uint8List(12);
    writeUint64BigEndian(ByteData.sublistView(nonce), 4, index);
    return nonce;
  }

  static List<int> _aad(Uint8List header, int index, bool last) {
    final aad = Uint8List(headerLength + 9);
    aad.setRange(0, headerLength, header);
    writeUint64BigEndian(ByteData.sublistView(aad), headerLength, index);
    aad[headerLength + 8] = last ? 1 : 0;
    return aad;
  }

  static void _checkChunkSize(int chunkSize) {
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw ArgumentError.value(chunkSize, 'chunkSize',
          'must be between $minChunkSize and $maxChunkSize');
    }
  }

  static Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(saltLength, (_) => random.nextInt(256)));
  }
}

/// A fixed-capacity byte buffer, refilled in place so a long stream never
/// grows memory.
class _ChunkBuffer {
  _ChunkBuffer(int capacity) : _bytes = Uint8List(capacity);

  Uint8List _bytes;
  int length = 0;

  bool get isFull => length == _bytes.length;

  /// Copies as much of [source] from [start] as fits; returns the count.
  int fill(List<int> source, int start) {
    final n = min(_bytes.length - length, source.length - start);
    _bytes.setRange(length, length + n, source, start);
    length += n;
    return n;
  }

  /// Hands over the filled bytes and starts a new buffer.
  Uint8List take() {
    final out = length == _bytes.length
        ? _bytes
        : Uint8List.fromList(Uint8List.sublistView(_bytes, 0, length));
    _bytes = Uint8List(_bytes.length);
    length = 0;
    return out;
  }
}
