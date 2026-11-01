// Identity & recovery (BUILD-SPEC §3.1).
//
// "Nothing else about identity exists anywhere": one 16-byte entropy,
// expanded via BLAKE2b to a 32-byte KDF root, from which crypto_kdf derives
// the Ed25519 signing identity (ctx PORCHSGN) and the X25519 box identity
// (ctx PORCHBOX) independently — no Ed→X conversion. The mailboxId is a hash
// of the signing public key; the server never links it to anything.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:sodium/sodium_sumo.dart' show SodiumSumo;

import 'mnemonic.dart' show isBip39Word;
import 'support/bip39_words.dart';
import 'support/bytes.dart';
import 'support/canonical_json.dart';

const _rootContext = 'porch/root/v1';
const _mailboxContext = 'porch/mbox/v1';
const _signKdfCtx = 'PORCHSGN'; // crypto_kdf contexts are exactly 8 chars
const _boxKdfCtx = 'PORCHBOX';
// v2: the 6 backup words. v1 (a person-picked PIN) is gone; no v1 file
// was ever made outside a test, as Porch has never run on a phone.
const _backupVersion = 2;
const _backupAd = 'porch/backup/v2';

/// The whole of a Porch identity, derived deterministically from [entropy].
class PorchIdentity {
  /// 16 bytes; what the 12 mnemonic words spell. Keystore-bound at rest.
  final Uint8List entropy;

  /// Ed25519 identity (signing). publicKey is what rosters carry.
  final KeyPair sign;

  /// X25519 identity (sealed-box recipient for grants/rotations).
  final KeyPair box;

  /// hash(sign_pk) — the anonymous mailbox address (base64url, no padding).
  final String mailboxId;

  PorchIdentity._(this.entropy, this.sign, this.box, this.mailboxId);

  factory PorchIdentity.fromEntropy(Sodium sodium, Uint8List entropy) {
    if (entropy.length != 16) {
      throw ArgumentError.value(
          entropy.length, 'entropy', 'must be exactly 16 bytes');
    }
    // root = BLAKE2b-256("porch/root/v1" ‖ entropy)
    final rootBytes = sodium.crypto.genericHash(
      message: concatBytes([utf8.encode(_rootContext), entropy]),
      outLen: 32,
    );
    final root = SecureKey.fromList(sodium, rootBytes);
    try {
      final signSeed = sodium.crypto.kdf.deriveFromKey(
        masterKey: root,
        context: _signKdfCtx,
        subkeyId: BigInt.one,
        subkeyLen: 32,
      );
      final boxSeed = sodium.crypto.kdf.deriveFromKey(
        masterKey: root,
        context: _boxKdfCtx,
        subkeyId: BigInt.one,
        subkeyLen: 32,
      );
      try {
        final sign = sodium.crypto.sign.seedKeyPair(signSeed);
        final box = sodium.crypto.box.seedKeyPair(boxSeed);
        return PorchIdentity._(
          Uint8List.fromList(entropy),
          sign,
          box,
          deriveMailboxId(sodium, sign.publicKey),
        );
      } finally {
        signSeed.dispose();
        boxSeed.dispose();
      }
    } finally {
      root.dispose();
    }
  }

  /// First launch: fresh random entropy (§3.1 step 1).
  factory PorchIdentity.generate(Sodium sodium) =>
      PorchIdentity.fromEntropy(sodium, sodium.randombytes.buf(16));
}

/// mailboxId = base64url(BLAKE2b-256("porch/mbox/v1" ‖ sign_pk)), no padding.
/// Byte-exactness with the Go relay is pinned by test vector.
String deriveMailboxId(Sodium sodium, Uint8List signPk) => b64urlNoPad(
      sodium.crypto.genericHash(
        message: concatBytes([utf8.encode(_mailboxContext), signPk]),
        outLen: 32,
      ),
    );

// ---------------------------------------------------------------------------
// Backup blob (§3.1 step 7): 6 backup words → Argon2id → XChaCha20-Poly1305
// over {entropy, stateSnapshot}. Restoring it is the full-recovery path;
// the 12 words alone are the identity-only path.
//
// The person never picks the backup's secret. A picked PIN of 4 digits
// fell to a few hours of guessing on one core, and the file is made to
// travel. Porch derives 6 words (66 bits) from the identity instead and
// shows them beside the 12, so a restore from the 12 words shows them
// again. sealBackup takes no password at all: no weak one can reach it.
// ---------------------------------------------------------------------------

const _backupWordsContext = 'porch/backup-words/v1';

/// How many words the backup passphrase has: 6 × 11 bits = 66 bits.
const backupPassphraseWordCount = 6;

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => 'BackupException: $message';
}

class BackupContents {
  final Uint8List entropy;
  final Map<String, Object?> stateSnapshot;
  const BackupContents({required this.entropy, required this.stateSnapshot});
}

/// The 6 backup words of the identity spelled by [entropy]: the first 66
/// bits of BLAKE2b("porch/backup-words/v1" ‖ entropy), as 11-bit indices
/// into the BIP39 list the 12 words use. Fixed by the identity, so the
/// words never need storing.
List<String> backupPassphrase(Sodium sodium, Uint8List entropy) {
  if (entropy.length != 16) {
    throw ArgumentError.value(
        entropy.length, 'entropy', 'must be exactly 16 bytes');
  }
  final digest = sodium.crypto.genericHash(
    message: concatBytes([utf8.encode(_backupWordsContext), entropy]),
    outLen: 16,
  );
  var acc = BigInt.zero;
  for (final b in digest) {
    acc = (acc << 8) | BigInt.from(b);
  }
  acc = acc >> (128 - 11 * backupPassphraseWordCount);
  final words = List<String>.filled(backupPassphraseWordCount, '');
  final mask = BigInt.from(0x7ff);
  for (var i = backupPassphraseWordCount - 1; i >= 0; i--) {
    words[i] = bip39English[(acc & mask).toInt()];
    acc = acc >> 11;
  }
  return words;
}

/// [raw] as typed, back to the one spelling Argon2id hashes: 6 list words,
/// lower case, single spaces. Null when it is not 6 list words.
String? normalizeBackupPassphrase(String raw) {
  final words = raw
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length != backupPassphraseWordCount) return null;
  if (!words.every(isBip39Word)) return null;
  return words.join(' ');
}

/// Spec default: Argon2id MODERATE (§3.1 step 7).
int defaultBackupOpsLimit(SodiumSumo sodium) =>
    sodium.crypto.pwhash.opsLimitModerate;

int defaultBackupMemLimit(SodiumSumo sodium) =>
    sodium.crypto.pwhash.memLimitModerate;

/// Blob layout (utf8 canonical JSON — self-describing so restore never
/// guesses parameters):
///   {"ct":b64, "mem":int, "nonce":b64, "ops":int, "salt":b64, "v":2}
/// ct = XChaCha20-Poly1305(key = Argon2id(words, salt, ops, mem),
///                         ad  = "porch/backup/v2",
///                         msg = canonical {entropy: b64, state: {...}})
/// words = the 6 backup words of [entropy], joined by single spaces.
Uint8List sealBackup(
  SodiumSumo sodium, {
  required Uint8List entropy,
  required Map<String, Object?> stateSnapshot,
  int? opsLimit,
  int? memLimit,
}) {
  final ops = opsLimit ?? defaultBackupOpsLimit(sodium);
  final mem = memLimit ?? defaultBackupMemLimit(sodium);
  final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
  final nonce = sodium.randombytes
      .buf(sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes);
  final key = _wordsKey(
      sodium, backupPassphrase(sodium, entropy).join(' '), salt, ops, mem);
  try {
    final ct = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
      message: canonicalJsonBytes({
        'entropy': b64(entropy),
        'state': stateSnapshot,
      }),
      nonce: nonce,
      key: key,
      additionalData: utf8.encode(_backupAd),
    );
    return canonicalJsonBytes({
      'v': _backupVersion,
      'salt': b64(salt),
      'ops': ops,
      'mem': mem,
      'nonce': b64(nonce),
      'ct': b64(ct),
    });
  } finally {
    key.dispose();
  }
}

/// Open a backup with the 6 backup words as the person typed them (case
/// and spaces do not matter). Everything is checked before Argon2id runs:
/// the words, the header, and that its cost parameters lie between
/// libsodium's minimum and SENSITIVE, so a crafted file cannot ask for
/// a terabyte of memory or hours of work.
BackupContents openBackup(
  SodiumSumo sodium, {
  required String passphrase,
  required Uint8List blob,
}) {
  final words = normalizeBackupPassphrase(passphrase);
  if (words == null) throw const BackupException('not 6 backup words');
  final Map<String, Object?> header;
  final Uint8List salt, nonce, ct;
  final int ops, mem;
  try {
    header = jsonDecode(utf8.decode(blob)) as Map<String, Object?>;
    if (header['v'] != _backupVersion) {
      throw const FormatException('bad version');
    }
    salt = b64decode(header['salt'] as String);
    nonce = b64decode(header['nonce'] as String);
    ct = b64decode(header['ct'] as String);
    ops = header['ops'] as int;
    mem = header['mem'] as int;
  } on Object {
    throw const BackupException('not a Porch backup blob');
  }
  final pw = sodium.crypto.pwhash;
  if (ops < pw.opsLimitMin ||
      ops > pw.opsLimitSensitive ||
      mem < pw.memLimitMin ||
      mem > pw.memLimitSensitive ||
      salt.length != pw.saltBytes) {
    throw const BackupException('backup parameters out of range');
  }
  final key = _wordsKey(sodium, words, salt, ops, mem);
  final Uint8List plain;
  try {
    plain = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
      cipherText: ct,
      nonce: nonce,
      key: key,
      additionalData: utf8.encode(_backupAd),
    );
  } on Object {
    // Wrong words and tampered blob are indistinguishable by design (AEAD).
    throw const BackupException('wrong words or corrupted backup');
  } finally {
    key.dispose();
  }
  try {
    final body = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
    return BackupContents(
      entropy: b64decode(body['entropy'] as String),
      stateSnapshot: (body['state'] as Map).cast<String, Object?>(),
    );
  } on Object {
    throw const BackupException('backup payload malformed');
  }
}

SecureKey _wordsKey(
        SodiumSumo sodium, String words, Uint8List salt, int ops, int mem) =>
    sodium.crypto.pwhash.call(
      outLen: 32,
      password: Int8List.fromList(utf8.encode(words)),
      salt: salt,
      opsLimit: ops,
      memLimit: mem,
    );
