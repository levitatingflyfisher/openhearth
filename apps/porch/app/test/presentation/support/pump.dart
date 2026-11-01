// Pump the real app root inside the app's root scope (porchProviderScope,
// retry off as in the app) wired to a UiWorld.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/app.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:porch_app/presentation/home/home_screen.dart';

import 'ui_world.dart';

Future<void> pumpPorch(WidgetTester tester, UiWorld u) async {
  // A tall phone-ish surface so whole screens fit; scrolling is still
  // exercised via tapItem's ensureVisible.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    porchProviderScope(overrides: u.overrides, child: const PorchApp()),
  );
  await _settle(tester);
}

/// Scroll the target into view, tap it, settle. The tight settle timeout
/// turns a would-be infinite animation into a fast, debuggable failure.
/// Lazily-built list children may not exist yet — scroll until they do.
Future<void> tapItem(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
  } else {
    await tester.ensureVisible(finder);
  }
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );

/// Pump an arbitrary screen under the same overrides (for direct
/// screen-level tests).
Future<void> pumpScreen(WidgetTester tester, UiWorld u, Widget screen) async {
  await tester.pumpWidget(
    porchProviderScope(
      overrides: u.overrides,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// Home's worded top-bar destinations ("Groups", "Settings").
Finder barAction(String label) => find.widgetWithText(OhBarAction, label);

/// Home's Settings lives in the worded More menu (a rare visit).
Future<void> openSettings(WidgetTester tester) async {
  await tapItem(tester, find.byTooltip('More'));
  await tapItem(tester, find.text('Settings'));
}

/// Home's refresh lives in the worded More menu.
Future<void> refreshNow(WidgetTester tester) async {
  await tapItem(tester, find.byTooltip('More'));
  await tapItem(tester, find.text('Refresh now'));
}

/// One segment ("On" / "Off") of Home's porch light control.
Finder lightSegment(String label) => find.descendant(
    of: find.byKey(porchLightKey), matching: find.text(label));

SegmentedButton<bool> _light(WidgetTester tester) =>
    tester.widget<SegmentedButton<bool>>(find.byKey(porchLightKey));

/// Whether the control currently shows the light as on.
bool lightShowsOn(WidgetTester tester) => _light(tester).selected.contains(true);

/// Whether the control can be used (there is a group to tell).
bool lightEnabled(WidgetTester tester) =>
    _light(tester).onSelectionChanged != null;
