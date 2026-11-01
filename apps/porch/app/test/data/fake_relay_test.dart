// W3-data: FakeRelay must mirror the Go relay's EXACT semantics — seq,
// atomic one-time join, proof pinning, delete-after-retrieval, TTLs on an
// injectable clock, caps — so repository and sync tests run against honest
// server behavior with zero services.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/fake_relay.dart';
import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/domain/domain.dart';

import '../domain/support/test_sodium.dart';

void main() {
  late FakeRelay relay;

  setUpAll(() async => loadTestSodium());

  setUp(() async {
    relay = FakeRelay(await loadTestSodium(), nowSec: 1_700_000_000);
  });

  Uint8List blobOf(List<int> bytes) => Uint8List.fromList(bytes);
  String id(String c) => c * 22;

  group('invites', () {
    test('create → join → second join is Gone (atomic one-time)', () async {
      await relay.createInvite(inviteId: id('a'), ttlHours: 72);
      await relay.joinInvite(inviteId: id('a'), blob: blobOf([1]));
      await expectLater(relay.joinInvite(inviteId: id('a'), blob: blobOf([2])),
          throwsA(isA<RelayGone>()));
    });

    test('duplicate create → Conflict; unknown join → NotFound', () async {
      await relay.createInvite(inviteId: id('a'), ttlHours: 1);
      await expectLater(relay.createInvite(inviteId: id('a'), ttlHours: 1),
          throwsA(isA<RelayConflict>()));
      await expectLater(relay.joinInvite(inviteId: id('b'), blob: blobOf([1])),
          throwsA(isA<RelayNotFound>()));
    });

    test('invite expires at its TTL: join answers NotFound after expiry',
        () async {
      await relay.createInvite(inviteId: id('a'), ttlHours: 1);
      relay.nowSec += 3601;
      await expectLater(relay.joinInvite(inviteId: id('a'), blob: blobOf([1])),
          throwsA(isA<RelayNotFound>()));
    });

    test('fetchJoin pins the first proof; a different proof is refused',
        () async {
      await relay.createInvite(inviteId: id('a'), ttlHours: 1);
      await relay.joinInvite(inviteId: id('a'), blob: blobOf([7]));
      final blob = await relay.fetchJoin(inviteId: id('a'), proof: 'p' * 43);
      expect(blob, [7]);
      // Same proof again: fine (Alice may re-fetch).
      await relay.fetchJoin(inviteId: id('a'), proof: 'p' * 43);
      await expectLater(relay.fetchJoin(inviteId: id('a'), proof: 'q' * 43),
          throwsA(isA<RelayNotFound>()));
    });

    test('grant round-trip: put (fetchProof pin) → take → deleted after take',
        () async {
      await relay.createInvite(inviteId: id('a'), ttlHours: 1);
      await relay.joinInvite(inviteId: id('a'), blob: blobOf([7]));
      await relay.fetchJoin(inviteId: id('a'), proof: 'p' * 43);
      await relay.putGrant(
          inviteId: id('a'), proof: 'p' * 43, blob: blobOf([9, 9]));
      // put with a non-pinned proof is refused
      await expectLater(
          relay.putGrant(inviteId: id('a'), proof: 'x' * 43, blob: blobOf([0])),
          throwsA(isA<RelayNotFound>()));
      final got = await relay.takeGrant(inviteId: id('a'), proof: 'g' * 43);
      expect(got, [9, 9]);
      // Deleted after retrieval (§4 row 5).
      await expectLater(relay.takeGrant(inviteId: id('a'), proof: 'g' * 43),
          throwsA(isA<RelayNotFound>()));
    });
  });

  group('mailbox', () {
    test('drain requires a valid signature and is atomic returned==deleted',
        () async {
      final sodium = await loadTestSodium();
      final me = PorchIdentity.fromEntropy(
          sodium, Uint8List.fromList(List.filled(16, 3)));
      await relay.mailboxPost(mailboxId: me.mailboxId, blob: blobOf([1]));
      await relay.mailboxPost(mailboxId: me.mailboxId, blob: blobOf([2]));

      final auth = buildDrainAuth(sodium,
          sign: me.sign, mailboxId: me.mailboxId, ts: relay.nowSec);
      final blobs = await relay.mailboxDrain(mailboxId: me.mailboxId, auth: auth);
      expect(blobs, [
        [1],
        [2]
      ]);
      // Replay of the same signature is refused (10 min cache).
      await expectLater(relay.mailboxDrain(mailboxId: me.mailboxId, auth: auth),
          throwsA(isA<RelayUnauthorized>()));
      // A fresh signature drains an empty box.
      final auth2 = buildDrainAuth(sodium,
          sign: me.sign, mailboxId: me.mailboxId, ts: relay.nowSec + 1);
      expect(await relay.mailboxDrain(mailboxId: me.mailboxId, auth: auth2),
          isEmpty);
    });

    test('stale timestamp and wrong key are Unauthorized', () async {
      final sodium = await loadTestSodium();
      final me = PorchIdentity.fromEntropy(
          sodium, Uint8List.fromList(List.filled(16, 3)));
      final other = PorchIdentity.fromEntropy(
          sodium, Uint8List.fromList(List.filled(16, 4)));
      await expectLater(
          relay.mailboxDrain(
              mailboxId: me.mailboxId,
              auth: buildDrainAuth(sodium,
                  sign: me.sign,
                  mailboxId: me.mailboxId,
                  ts: relay.nowSec - 301)),
          throwsA(isA<RelayUnauthorized>()));
      await expectLater(
          relay.mailboxDrain(
              mailboxId: me.mailboxId,
              auth: buildDrainAuth(sodium,
                  sign: other.sign,
                  mailboxId: me.mailboxId,
                  ts: relay.nowSec)),
          throwsA(isA<RelayUnauthorized>()));
    });

    test('depth cap 200 → RateLimited', () async {
      for (var i = 0; i < 200; i++) {
        await relay.mailboxPost(mailboxId: 'm' * 43, blob: blobOf([i & 0xff]));
      }
      await expectLater(relay.mailboxPost(mailboxId: 'm' * 43, blob: blobOf([0])),
          throwsA(isA<RelayRateLimited>()));
    });
  });

  group('presence', () {
    test('slot overwrite updates; native TTL expiry empties the channel',
        () async {
      await relay.presencePost(
          channelId: 'c' * 43, slotId: 's' * 22, blob: blobOf([1]), ttlSec: 100);
      await relay.presencePost(
          channelId: 'c' * 43, slotId: 's' * 22, blob: blobOf([2]), ttlSec: 100);
      var slots = await relay.presenceGet('c' * 43);
      expect(slots, hasLength(1));
      expect(slots.single.blob, [2]);
      expect(slots.single.expiresAt, relay.nowSec + 100);

      relay.nowSec += 101;
      slots = await relay.presenceGet('c' * 43);
      expect(slots, isEmpty, reason: 'presence cannot exist after expiry');
    });

    test('1 KiB blob cap → TooLarge; ttl cap → BadRequest', () async {
      await expectLater(
          relay.presencePost(
              channelId: 'c' * 43,
              slotId: 's' * 22,
              blob: Uint8List(1025),
              ttlSec: 60),
          throwsA(isA<RelayTooLarge>()));
      await expectLater(
          relay.presencePost(
              channelId: 'c' * 43,
              slotId: 's' * 22,
              blob: blobOf([1]),
              ttlSec: 14701),
          throwsA(isA<RelayBadRequest>()));
    });
  });

  group('bulletin', () {
    test('seq is monotonic per channel; afterSeq pages', () async {
      expect(await relay.bulletinPost(channelId: 'c' * 43, blob: blobOf([1])), 1);
      expect(await relay.bulletinPost(channelId: 'c' * 43, blob: blobOf([2])), 2);
      expect(await relay.bulletinPost(channelId: 'd' * 43, blob: blobOf([3])), 1);
      final entries = await relay.bulletinGet('c' * 43, afterSeq: 1);
      expect(entries, hasLength(1));
      expect(entries.single.seq, 2);
      expect(entries.single.blob, [2]);
    });

    test('ring keeps last 8 unpinned; pinned survive ring pressure', () async {
      final pinSeq = await relay.bulletinPost(
          channelId: 'c' * 43, blob: blobOf([99]), pinned: true, ttlSec: 3600);
      for (var i = 0; i < 10; i++) {
        await relay.bulletinPost(channelId: 'c' * 43, blob: blobOf([i]));
      }
      final entries = await relay.bulletinGet('c' * 43);
      final unpinned = entries.where((e) => !e.pinned).toList();
      expect(unpinned, hasLength(8), reason: 'ring of 8');
      expect(unpinned.first.blob, [2], reason: 'oldest two evicted');
      final pins = entries.where((e) => e.pinned).toList();
      expect(pins, hasLength(1));
      expect(pins.single.seq, pinSeq);
      expect(pins.single.expiresAt, relay.nowSec + 3600);
    });

    test('pinned entries die by their own TTL', () async {
      await relay.bulletinPost(
          channelId: 'c' * 43, blob: blobOf([1]), pinned: true, ttlSec: 60);
      relay.nowSec += 61;
      expect(await relay.bulletinGet('c' * 43), isEmpty);
    });

    test('unpinned with nonzero ttlSec is BadRequest (relay parity)',
        () async {
      await expectLater(
          relay.bulletinPost(channelId: 'c' * 43, blob: blobOf([1]), ttlSec: 60),
          throwsA(isA<RelayBadRequest>()));
    });
  });

  group('failure injection', () {
    test('offline: every call throws RelayUnreachable and nothing lands',
        () async {
      relay.offline = true;
      await expectLater(
          relay.presencePost(
              channelId: 'c' * 43, slotId: 's' * 22, blob: blobOf([1]), ttlSec: 9),
          throwsA(isA<RelayUnreachable>()));
      await expectLater(
          relay.bulletinPost(channelId: 'c' * 43, blob: blobOf([1])),
          throwsA(isA<RelayUnreachable>()));
      relay.offline = false;
      expect(await relay.presenceGet('c' * 43), isEmpty);
      expect(await relay.bulletinGet('c' * 43), isEmpty);
    });

    test('the call log records op names for ordering assertions', () async {
      await relay.presenceGet('c' * 43);
      await relay.bulletinGet('c' * 43);
      expect(relay.callLog, ['presenceGet', 'bulletinGet']);
    });
  });
}
