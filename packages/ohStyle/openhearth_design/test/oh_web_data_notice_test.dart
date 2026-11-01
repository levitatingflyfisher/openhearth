import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'support/package_fonts.dart';

/// On the web, every fleet app keeps its data in the browser. A family
/// opening an app from a link must be told once, plainly, that clearing the
/// browser's website data erases it (OpenHearth roadmap, problem 2). The
/// words were checked by a blind reader and live here once.
void main() {
  setUpAll(loadPackageFontsAsConsumerSees);

  test('the words are exactly the checked ones', () {
    expect(
        ohWebDataNotice,
        'Your data stays on this device, in this browser. If you clear the '
        'browser’s website data, it is erased.');
  });

  Future<void> pump(WidgetTester tester, double width, double scale,
      {required bool web}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: OhTheme.light(),
      builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!),
      home: Scaffold(
          body: Column(children: [
        OhWebDataNotice(onWeb: web),
        const Text('app content'),
      ])),
    ));
  }

  testWidgets('off the web it draws nothing', (tester) async {
    await pump(tester, 360, 1.0, web: false);
    expect(find.text(ohWebDataNotice), findsNothing);
    expect(tester.getSize(find.byType(OhWebDataNotice)), Size.zero);
  });

  testWidgets('on the web it shows the line in the quiet small style, '
      'with nothing to dismiss', (tester) async {
    await pump(tester, 360, 1.0, web: true);
    expect(find.text(ohWebDataNotice), findsOneWidget);
    final ctx = tester.element(find.text(ohWebDataNotice));
    final text = tester.widget<Text>(find.text(ohWebDataNotice));
    final shown = DefaultTextStyle.of(ctx).style.merge(text.style);
    expect(shown.fontSize, Theme.of(ctx).textTheme.bodySmall!.fontSize);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  test('it follows the platform by default', () {
    expect(const OhWebDataNotice().onWeb, isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits at 320 dp x $scale with no overflow', (tester) async {
      await pump(tester, 320, scale, web: true);
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.text(ohWebDataNotice));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(320));
    });
  }

  testWidgets('ohWebDataNoticeBuilder puts the line above every screen of '
      'a MaterialApp, with the screen filling the rest', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OhTheme.light(),
      builder: (context, child) =>
          ohWebDataNoticeBuilder(context, child, onWeb: true),
      home: const Scaffold(body: Text('app content')),
    ));
    expect(tester.takeException(), isNull);
    final notice = tester.getRect(find.text(ohWebDataNotice));
    final content = tester.getRect(find.text('app content'));
    expect(notice.bottom, lessThanOrEqualTo(content.top));
    expect(tester.getSize(find.byType(Scaffold)).height,
        lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });

  // Above the Navigator there is no Material, and MaterialApp's fallback
  // text style there draws yellow underlines. The theme’s bodySmall sets
  // every part of it, underline included; this keeps it that way.
  testWidgets('through the builder the line has no debug underline and the '
      'theme’s small text style', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OhTheme.light(),
      builder: (context, child) =>
          ohWebDataNoticeBuilder(context, child, onWeb: true),
      home: const Scaffold(body: Text('app content')),
    ));
    final ctx = tester.element(find.text(ohWebDataNotice));
    final text = tester.widget<Text>(find.text(ohWebDataNotice));
    final shown = DefaultTextStyle.of(ctx).style.merge(text.style);
    final small = Theme.of(ctx).textTheme.bodySmall!;
    expect(shown.decoration, anyOf(isNull, TextDecoration.none));
    expect(shown.fontFamily, small.fontFamily);
    expect(shown.fontWeight, small.fontWeight);
    expect(shown.fontSize, small.fontSize);
  });

  testWidgets('off the web the builder hands back the screen untouched',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          ohWebDataNoticeBuilder(context, child, onWeb: false),
      home: const Scaffold(body: Text('app content')),
    ));
    expect(find.byType(OhWebDataNotice), findsNothing);
  });

  testWidgets('debugOhWebDataNoticeOnWeb lets an app test show the strip '
      'through its own MaterialApp builder', (tester) async {
    debugOhWebDataNoticeOnWeb = true;
    addTearDown(() => debugOhWebDataNoticeOnWeb = null);
    await tester.pumpWidget(MaterialApp(
      theme: OhTheme.light(),
      builder: ohWebDataNoticeBuilder,
      home: const Scaffold(body: Text('app content')),
    ));
    expect(find.text(ohWebDataNotice), findsOneWidget);
  });
}
