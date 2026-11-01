// W4 acceptance: the house accessibility sweep — Home (empty), Home with a
// live feed + my light on, and GroupDetail, at 320 dp and textScale 1–3.
// An overflow anywhere surfaces as a FlutterError and fails the pump.
// Goldens pin the three screens at each scale (regenerate with
// `flutter test --update-goldens test/presentation/a11y_sweep_test.dart`).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/relay_config.dart';
import 'package:porch_app/presentation/app.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> pumpNarrow(
    WidgetTester tester, UiWorld u, double textScale) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(overrides: u.overrides, child: const PorchApp()),
  );
  await tester.pumpAndSettle();
}

/// Home with a friend's light on (and an admin roster for GroupDetail).
Future<UiWorld> liveFeedWorld() async {
  final u = await UiWorld.onboarded();
  final bob = await addFriend(u, contactNote: 'Call my cell');
  await bob.presence.publishAvailable(
      tag: '\u{1F4D6}', expiresAt: u.world.clock.nowSec + 3600);
  return u;
}

void main() {
  for (final scale in const [1.0, 2.0, 3.0]) {
    testWidgets('Home (empty) survives 320 dp at ×$scale', (tester) async {
      final u = await UiWorld.onboarded();
      await pumpNarrow(tester, u, scale);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_empty_${scale.toInt()}x.png'),
      );
    });

    testWidgets('Home (live feed) survives 320 dp at ×$scale',
        (tester) async {
      final u = await liveFeedWorld();
      await pumpNarrow(tester, u, scale);
      // My light on too: exercises the on-state card. Do it through the
      // real sheet at this size.
      await tapItem(tester, lightSegment('On'));
      await tapItem(tester, find.text('Turn on the porch light'));
      await refreshNow(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feed_${scale.toInt()}x.png'),
      );
    });

    // Overflow-only (no golden): the out-of-box Home every new install
    // shows — no relay set, then a light turned on locally.
    testWidgets('Home (no relay set) survives 320 dp at ×$scale',
        (tester) async {
      final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
      await pumpNarrow(tester, u, scale);
      expect(find.text('No relay set up'), findsOneWidget);
      await tapItem(tester, lightSegment('On'));
      await tapItem(tester, find.text('Turn on the porch light'));
      expect(find.text('Your light is on, on this phone only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Restore-from-backup step survives 320 dp at ×$scale',
        (tester) async {
      final u = await UiWorld.fresh();
      await pumpNarrow(tester, u, scale);
      await tapItem(tester, find.text('Restore an existing identity'));
      await tapItem(tester, find.text('Restore from a backup file instead'));
      // At ×3 the button sits below the fold of the lazily built list.
      await tester.scrollUntilVisible(find.text('Restore from backup'), 120,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('GroupDetail survives 320 dp at ×$scale', (tester) async {
      final u = await liveFeedWorld();
      await pumpNarrow(tester, u, scale);
      await tapItem(tester, barAction('Groups'));
      await tapItem(tester, find.text('My Porch'));
      await tapItem(tester, find.text('Invite a friend'));
      await tapItem(tester, find.text('Done'));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/group_detail_${scale.toInt()}x.png'),
      );
    });
  }
}
