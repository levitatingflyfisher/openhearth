import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'support/package_fonts.dart';

/// Two riverpod-3 audits found a failed read drawn as an empty list
/// (Bulwark's Progress and Shopping screens, through `valueOrNull ?? []`)
/// and as Flutter's grey error widget (Peckish's main screens). A household
/// must tell "you have nothing here" from "the app could not read this", and
/// have one plain way to try again. `OhReadError` is that view.
void main() {
  setUpAll(() async {
    await loadPackageFontsAsConsumerSees();
    await loadMaterialIconsForGoldens();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 800),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? OhTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('shows the default title, the default line and Try again',
      (tester) async {
    await pump(tester, OhReadError(onRetry: () {}));
    expect(find.text(OhErrorMessages.readFailedTitle), findsOneWidget);
    expect(find.text(OhErrorMessages.readFailed), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  test('the default words say what happened and that nothing was deleted', () {
    const words =
        '${OhErrorMessages.readFailedTitle} ${OhErrorMessages.readFailed}';
    expect(words, contains("couldn't read"));
    expect(words, contains('on this device'));
    expect(words, contains('deletes nothing'));
    // Fleet copy rules: no hedging, no em dash.
    for (final banned in ['might', 'possibly', 'maybe', 'perhaps', '—']) {
      expect(words.toLowerCase(), isNot(contains(banned)), reason: banned);
    }
  });

  testWidgets('Try again calls the callback once per tap', (tester) async {
    var retried = 0;
    await pump(tester, OhReadError(onRetry: () => retried++));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('Try again is at least 48dp tall', (tester) async {
    await pump(tester, OhReadError(onRetry: () {}));
    final size = tester.getSize(find.bySubtype<FilledButton>());
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('the detail line shows only when the app passes one',
      (tester) async {
    await pump(tester, OhReadError(onRetry: () {}));
    expect(find.text('Shopping list'), findsNothing);

    await pump(
      tester,
      OhReadError(onRetry: () {}, detail: 'Shopping list'),
    );
    expect(find.text('Shopping list'), findsOneWidget);
  });

  testWidgets('an app may name the part in the title', (tester) async {
    await pump(
      tester,
      OhReadError(
        onRetry: () {},
        title: "Couldn't read your shopping list",
      ),
    );
    expect(find.text("Couldn't read your shopping list"), findsOneWidget);
    expect(find.text(OhErrorMessages.readFailedTitle), findsNothing);
    expect(find.text(OhErrorMessages.readFailed), findsOneWidget);
  });

  testWidgets('no technical text on screen; the error waits behind Details',
      (tester) async {
    final error = StateError('SqliteException(11): database disk image');
    await pump(tester, OhReadError(onRetry: () {}));
    expect(find.text('Details'), findsNothing);

    await pump(tester, OhReadError(onRetry: () {}, error: error));
    expect(find.textContaining('SqliteException'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('SqliteException'),
    );
  });

  testWidgets('no overflow at 3x text on a 320dp phone', (tester) async {
    var retried = 0;
    await pump(
      tester,
      OhReadError(
        onRetry: () => retried++,
        title: "Couldn't read this household's shared shopping list",
        detail: 'Shopping list, Saturday market run',
        error: StateError('x'),
      ),
      size: const Size(320, 640),
      textScale: 3.0,
    );
    expect(tester.takeException(), isNull);
    // At 3x the button sits below the fold: scroll to it, then tap, or the
    // tap lands on whatever owns that point and the test proves nothing.
    await tester.ensureVisible(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, ThemeData Function()>{
    'light': OhTheme.light,
    'hearthDark': OhTheme.hearthDark,
    'night': OhTheme.night,
  }.entries) {
    testWidgets('golden under OhTheme.${entry.key}()', (tester) async {
      await pump(
        tester,
        OhReadError(onRetry: () {}, detail: 'Shopping list'),
        size: const Size(360, 640),
        theme: entry.value(),
      );
      expect(tester.takeException(), isNull);
      // The detail is quieter than the line above it, and still clears the
      // text contrast floor: onSurfaceVariant is held in contrast_test.dart.
      final detail = tester.widget<Text>(find.text('Shopping list'));
      expect(detail.style?.color, entry.value().colorScheme.onSurfaceVariant);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/oh_read_error_${entry.key}.png'),
      );
    });
  }
}
