// W4 acceptance: the home screen — big Available button (groups, expiry,
// tag), the feed with countdown + contact note, typed-honesty staleness,
// optimistic offline tap, and the 30-day feedback prompt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/group_repo.dart';
import 'package:porch_app/data/porch_state.dart';

import 'package:porch_app/presentation/home/home_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {

  testWidgets('empty feed: honest empty state + the Available button',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    expect(find.textContaining("Nobody’s on the porch"), findsOneWidget);
    expect(find.byKey(porchLightKey), findsOneWidget);
    expect(lightShowsOn(tester), isFalse);
  });

  testWidgets('tap Available → sheet: pick 2 h + a tag preset → my light is '
      'on with an honest countdown; the relay got the encrypted post',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);

    await tapItem(tester, lightSegment('On'));
    // The sheet: groups, durations, tags.
    expect(find.text('My Porch'), findsWidgets);
    await tapItem(tester, find.text('2 h'));
    await tapItem(tester, find.text('walking')); // a preset
    await tapItem(tester, find.text('Turn on the porch light'));

    expect(find.text("You’re on the porch"), findsOneWidget);
    expect(find.textContaining('2 h left'), findsOneWidget);
    expect(find.textContaining('walking'), findsWidgets);
    expect(u.world.relay.callLog, contains('presencePost'));

    // Off → tombstone; the same control shows the light off.
    await tapItem(tester, lightSegment('Off'));
    expect(find.byKey(porchLightKey), findsOneWidget);
    expect(lightShowsOn(tester), isFalse);
  });

  testWidgets('optimistic tap: relay dead → the light still flips instantly '
      '(outbox queues; nothing throws)', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    u.world.relay.offline = true;

    await tapItem(tester, lightSegment('On'));
    await tapItem(tester, find.text('Turn on the porch light'));

    expect(find.text("You’re on the porch"), findsOneWidget);
    final state = await u.store.load();
    expect(state!.outbox, isNotEmpty, reason: 'queued for reconnect');
  });

  testWidgets('sheet group multi-select: deselecting a group publishes only '
      'to the others', (tester) async {
    final u = await UiWorld.onboarded();
    final env = await u.env();
    await GroupRepo(env).createGroup('Book club');
    await pumpPorch(tester, u);

    await tapItem(tester, lightSegment('On'));
    await tapItem(tester, find.text('Book club')); // deselect
    await tapItem(tester, find.text('Turn on the porch light'));

    final state = (await u.store.load())!;
    final porch = state.groups.firstWhere((g) => g.name == 'My Porch');
    final club = state.groups.firstWhere((g) => g.name == 'Book club');
    expect(state.presence[porch.groupUuid]?.entries, isNotEmpty);
    expect(state.presence[club.groupUuid]?.entries ?? [], isEmpty);
  });

  testWidgets('feed: a friend renders with name, tag, countdown and group; '
      'tapping shows the contact note from the roster', (tester) async {
    final u = await UiWorld.onboarded();
    final bob = await addFriend(u, contactNote: 'Call my cell: 555-0100');
    await bob.presence.publishAvailable(
        tag: '\u{1F4D6}', expiresAt: u.world.clock.nowSec + 3600);

    await pumpPorch(tester, u);
    await refreshNow(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('\u{1F4D6}'), findsWidgets);
    expect(find.textContaining('1 h left'), findsWidgets);
    expect(find.textContaining('My Porch'), findsWidgets);

    await tapItem(tester, find.text('Bob'));
    expect(find.text('Call my cell: 555-0100'), findsOneWidget);
  });

  testWidgets('typed honesty: >15 min-old snapshot renders the staleness '
      'line; a fresh one does not', (tester) async {
    final u = await UiWorld.onboarded();
    final bob = await addFriend(u);
    await bob.presence.publishAvailable(
        expiresAt: u.world.clock.nowSec + 4 * 3600);

    await pumpPorch(tester, u);
    await refreshNow(tester);
    expect(find.textContaining('as of'), findsNothing,
        reason: 'fresh data needs no disclaimer');

    // 20 minutes pass; the relay is unreachable, so the snapshot cannot
    // renew — the UI must SAY so instead of silently pretending.
    u.world.relay.offline = true;
    u.advance(20 * 60);
    await refreshNow(tester);
    expect(find.textContaining('as of 20 min ago'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget,
        reason: 'last-known state stays visible, honestly aged');
  });

  testWidgets('30-day feedback prompt: shown when due, one tap dismisses '
      'for another 30 days', (tester) async {
    final u = await UiWorld.onboarded();
    final state = (await u.store.load())!;
    state.metrics.add(MetricsDay(
        date: '2026-06-01',
        publishes: 1,
        firstAt: u.world.clock.nowSec - 31 * 86400,
        lastAt: u.world.clock.nowSec - 31 * 86400));
    await u.store.save(state);

    await pumpPorch(tester, u);
    expect(find.textContaining("How’s Porch working"), findsOneWidget);

    await tapItem(tester, find.byIcon(Icons.close));
    expect(find.textContaining("How’s Porch working"), findsNothing);
    expect((await u.store.load())!.feedback.lastPromptAt,
        u.world.clock.nowSec);
  });
}
