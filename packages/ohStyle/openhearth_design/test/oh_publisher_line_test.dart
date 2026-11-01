import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'support/package_fonts.dart';

/// Every fleet app names its publisher in one plain line, the same words in
/// each app (board-0166, board-0170). The words live here once so no app can
/// spell them its own way.
void main() {
  setUpAll(loadPackageFontsAsConsumerSees);

  test('the words are exactly the ruled ones', () {
    expect(ohPublisherLine, 'Published by Intergenerational Symbolic Systems');
  });

  Future<void> pump(WidgetTester tester, double width, double scale) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: OhTheme.light(),
      builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!),
      home: const Scaffold(
          body: Padding(
              padding: EdgeInsets.all(OhSpacing.md), child: OhPublisherLine())),
    ));
  }

  testWidgets('shows the line, centred, in the quiet small style',
      (tester) async {
    await pump(tester, 360, 1.0);
    expect(find.text(ohPublisherLine), findsOneWidget);
    final text = tester.widget<Text>(find.text(ohPublisherLine));
    expect(text.textAlign, TextAlign.center);
    final ctx = tester.element(find.text(ohPublisherLine));
    final small = Theme.of(ctx).textTheme.bodySmall!;
    final shown = DefaultTextStyle.of(ctx).style.merge(text.style);
    expect(shown.fontSize, small.fontSize);
    expect(shown.color, small.color);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits at 320 dp x $scale with no overflow', (tester) async {
      await pump(tester, 320, scale);
      expect(tester.takeException(), isNull);
      expect(find.text(ohPublisherLine), findsOneWidget);
      final box = tester.getRect(find.text(ohPublisherLine));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(320));
    });
  }
}
