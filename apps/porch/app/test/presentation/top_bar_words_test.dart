// Fleet ruling on top bars: icon plus a short visible word; a tooltip is
// never a command's only name. Checked where it is hardest: the primary
// sweep profile (360 dp x 1.3) and the house floor (320 dp x 3.0).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/app.dart';
import 'package:porch_app/presentation/groups/groups_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> _pumpAt(
    WidgetTester tester, UiWorld u, Widget app, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(overrides: u.overrides, child: app));
  await tester.pumpAndSettle();
}

void main() {
  for (final (size, scale) in const [
    (Size(360, 640), 1.3),
    (Size(320, 640), 3.0),
  ]) {
    final at = '${size.width.toInt()} dp x $scale';

    testWidgets('Home: the title is whole and every command is named at $at',
        (tester) async {
      final u = await UiWorld.onboarded();
      await _pumpAt(tester, u, const PorchApp(), size, scale);
      expect(tester.takeException(), isNull);
      // The title is never squeezed by the commands (it was "Po…" at 320
      // dp x 3.0). The bar folds by space, the fleet's OhBarActions rule.
      final title = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(AppBar), matching: find.text('Porch')));
      expect(title.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(title.size.width + 0.5),
          reason: 'the Porch title is cut');
      // More included: it is Home's only route to the theme, so a tooltip
      // cannot be its only name at everyday sizes; past the fold the word
      // is its tooltip and screen-reader name.
      for (final word in ['Groups', 'More']) {
        final label = find.descendant(
            of: find.byType(AppBar), matching: find.text(word));
        if (scale <= 1.3) {
          expect(label, findsOneWidget, reason: '$word has no visible word');
          final r = tester.getRect(label);
          expect(r.right, lessThanOrEqualTo(size.width), reason: word);
        } else {
          expect(find.bySemanticsLabel(word), findsOneWidget, reason: word);
        }
      }
      // The third action is a worded menu: its items are words.
      await tapItem(tester, find.byTooltip('More'));
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Refresh now'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('Groups: the add button says what it adds at $at',
        (tester) async {
      final u = await UiWorld.onboarded();
      await _pumpAt(
          tester, u, const MaterialApp(home: GroupsScreen()), size, scale);
      expect(tester.takeException(), isNull);
      expect(
          find.descendant(
              of: find.byType(FloatingActionButton),
              matching: find.text('New group')),
          findsOneWidget);
    });
  }
}
