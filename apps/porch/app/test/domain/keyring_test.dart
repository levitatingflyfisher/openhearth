// Group-key lifecycle (BUILD-SPEC §3.2): the group key IS the group. Its
// derivations are the routing invariant — rotating the key rotates the wire
// address. Policy: encrypt newest, decrypt last 2, prune retired after 7 days.
import 'dart:typed_data';

import 'package:porch_app/domain/keyring.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late Sodium sodium;
  setUpAll(() async {
    sodium = await loadTestSodium();
  });

  Uint8List gkOf(int fill) => Uint8List.fromList(List.filled(32, fill));

  group('derivations from gk (§3.2 step 2)', () {
    test('channelId is deterministic, 32 bytes base64url-no-pad', () {
      final a = deriveChannelId(sodium, gkOf(1));
      expect(a, deriveChannelId(sodium, gkOf(1)));
      expect(b64urlNoPadDecode(a), hasLength(32));
      expect(a, isNot(deriveChannelId(sodium, gkOf(2))));
    });

    test('channelId differs from the raw key (KDF, not identity)', () {
      expect(b64urlNoPadDecode(deriveChannelId(sodium, gkOf(1))),
          isNot(equals(gkOf(1))));
    });

    test('slotId is per-member, per-epoch-key, 16 bytes', () {
      final alice = Uint8List.fromList(List.generate(32, (i) => i));
      final bob = Uint8List.fromList(List.generate(32, (i) => 100 + i));
      final slotA = deriveSlotId(sodium, gkOf(1), alice);
      expect(slotA, deriveSlotId(sodium, gkOf(1), alice));
      expect(b64urlNoPadDecode(slotA), hasLength(16));
      expect(slotA, isNot(deriveSlotId(sodium, gkOf(1), bob)));
      // Rotation moves everyone to fresh slots: same member, new key → new id.
      expect(slotA, isNot(deriveSlotId(sodium, gkOf(2), alice)));
    });

    test('bulletin writer id is per-member, per-epoch-key, 16 bytes, '
        'and unlike the presence slot id', () {
      final alice = Uint8List.fromList(List.generate(32, (i) => i));
      final bob = Uint8List.fromList(List.generate(32, (i) => 100 + i));
      final writerA = deriveBulletinWriterId(sodium, gkOf(1), alice);
      expect(writerA, deriveBulletinWriterId(sodium, gkOf(1), alice));
      expect(b64urlNoPadDecode(writerA), hasLength(16));
      expect(writerA, hasLength(22)); // the relay takes 16..64 id chars
      expect(writerA, isNot(deriveBulletinWriterId(sodium, gkOf(1), bob)));
      expect(writerA, isNot(deriveBulletinWriterId(sodium, gkOf(2), alice)));
      // The relay must not be able to tie a member's bulletins to their
      // presence: the two ids share nothing.
      expect(writerA, isNot(deriveSlotId(sodium, gkOf(1), alice)));
    });

    test('bulletin writer id matches its spec: BLAKE2b-128 keyed by gk '
        'over "porch/bulletin-writer/v1" ‖ member sign pk', () {
      final alice = Uint8List.fromList(List.generate(32, (i) => i));
      // Computed apart from libsodium, with Python's hashlib.blake2b.
      expect(deriveBulletinWriterId(sodium, gkOf(1), alice),
          '3IznLwMyDJKTtgSLMsDGBg');
    });

    test('bulletin writer id refuses a group key of the wrong length', () {
      expect(
          () => deriveBulletinWriterId(
              sodium, Uint8List(16), Uint8List(32)),
          throwsArgumentError);
    });

    test('pushTopic is 12 bytes and dormant-deterministic (§1.3)', () {
      final t = derivePushTopic(sodium, gkOf(1));
      expect(t, hasLength(12));
      expect(t, derivePushTopic(sodium, gkOf(1)));
      expect(t, isNot(equals(derivePushTopic(sodium, gkOf(2)))));
    });

    test('channelId / slotKey / pushTopic are domain-separated', () {
      // All derive from the same gk; contexts must make them unrelated.
      final ch = b64urlNoPadDecode(deriveChannelId(sodium, gkOf(1)));
      final topic = derivePushTopic(sodium, gkOf(1));
      expect(ch.sublist(0, 12), isNot(equals(topic)));
    });
  });

  group('GroupKeyring policy (§3.2 step 3)', () {
    test('genesis starts at epoch 1, that key encrypts', () {
      final kr = GroupKeyring.genesis(gkOf(1));
      expect(kr.current.epoch, 1);
      expect(kr.current.gk, gkOf(1));
      expect(kr.current.retiredAt, isNull);
      expect(kr.decryptable.map((k) => k.epoch), [1]);
    });

    test('a member granted at epoch e starts there', () {
      final kr = GroupKeyring.fromGrant(epoch: 4, gk: gkOf(4));
      expect(kr.current.epoch, 4);
    });

    test('adopt retires the old epoch and keeps exactly last 2', () {
      var kr = GroupKeyring.genesis(gkOf(1));
      kr = kr.adopt(epoch: 2, gk: gkOf(2), nowSec: 1000);
      expect(kr.current.epoch, 2);
      expect(kr.decryptable.map((k) => k.epoch), [2, 1]);
      expect(kr.decryptable[1].retiredAt, 1000);

      kr = kr.adopt(epoch: 3, gk: gkOf(3), nowSec: 2000);
      expect(kr.decryptable.map((k) => k.epoch), [3, 2],
          reason: 'epoch 1 must fall off — decrypt last 2 only');
    });

    test('adopt rejects non-advancing epochs (replayed rotation)', () {
      final kr = GroupKeyring.genesis(gkOf(1)).adopt(
          epoch: 2, gk: gkOf(2), nowSec: 0);
      expect(() => kr.adopt(epoch: 2, gk: gkOf(9), nowSec: 1),
          throwsArgumentError);
      expect(() => kr.adopt(epoch: 1, gk: gkOf(9), nowSec: 1),
          throwsArgumentError);
    });

    test('prune drops retired epochs after 7 days, never the current', () {
      var kr = GroupKeyring.genesis(gkOf(1))
          .adopt(epoch: 2, gk: gkOf(2), nowSec: 1000);
      const week = 7 * 86400;
      expect(kr.prune(1000 + week).decryptable.map((k) => k.epoch), [2, 1],
          reason: 'exactly 7d is still within grace');
      expect(kr.prune(1000 + week + 1).decryptable.map((k) => k.epoch), [2]);
    });

    test('rejects a group key that is not 32 bytes', () {
      expect(() => GroupKeyring.genesis(Uint8List(16)), throwsArgumentError);
    });
  });
}
