// Release gate (fleet roadmap item 24, conformance C5-primaryScreens): at
// 360 dp x 1.3 text each primary screen's main action is on screen and
// tappable (scrolling to it is fine), then the same screen survives
// 320 dp x 3.0 without overflowing. Rendered in porch's real theme.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/presentation/app.dart';
import 'package:porch_app/presentation/home/home_screen.dart';
import 'package:porch_app/presentation/onboarding/onboarding_flow.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Widget _app(UiWorld u, Widget screen) => ProviderScope(
      overrides: u.overrides,
      child: MaterialApp(
        theme: OhTheme.light(appAccent: porchAmberLight),
        home: screen,
      ),
    );

void main() {
  testWidgets('HomeScreen: the porch light control at 360 dp x 1.3',
      (tester) async {
    final u = await UiWorld.onboarded();
    await runPrimaryActionSweep(
      tester,
      pumpScreen: () => tester.pumpWidget(_app(u, const HomeScreen())),
      primaryAction: lightSegment('On'),
    );
  });

  testWidgets('OnboardingFlow: the first step at 360 dp x 1.3',
      (tester) async {
    final u = await UiWorld.fresh();
    await runPrimaryActionSweep(
      tester,
      pumpScreen: () => tester
          .pumpWidget(_app(u, const OnboardingFlow(hasIdentity: false))),
      primaryAction: find.text("I’m 13 or older"),
    );
  });
}
