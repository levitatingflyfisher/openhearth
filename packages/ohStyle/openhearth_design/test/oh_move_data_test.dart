import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'support/package_fonts.dart';

/// Each web app moves from the shared old origin to its own address (owner
/// ruling, 15 Nov 2026). The move page at the old origin shows what it
/// found and saves the app's own backup file; it never writes. The offer at
/// the new address points a returning family back to it.
void main() {
  setUpAll(loadPackageFontsAsConsumerSees);
  tearDown(debugResetOhMovedHereOffer);

  group('the addresses', () {
    test('the move page lives in the landing site at /move/<app>/', () {
      expect(ohMovePageUrl('stilllife'),
          'https://levitatingflyfisher.github.io/move/stilllife/');
    });
    test('the new address is the app’s own subdomain', () {
      expect(ohNewAddressUrl('stilllife.familyflourishing.org'),
          'https://stilllife.familyflourishing.org/');
    });
  });

  group('the words', () {
    test('move screen', () {
      expect(ohMoveTitle('Still Life'), 'Still Life has moved');
      expect(ohMoveLivesAt('Still Life', 'stilllife.familyflourishing.org'),
          'Still Life now lives at stilllife.familyflourishing.org.');
      expect(ohMoveFound(0), 'We found no records saved in this browser.');
      expect(ohMoveFound(1), 'We found 1 record saved in this browser.');
      expect(ohMoveFound(12), 'We found 12 records saved in this browser.');
      expect(ohMoveCounting, 'Counting your records…');
      expect(ohMoveCountFailed,
          'We couldn’t count your records, but nothing was removed. You can '
          'still save a backup file.');
      expect(ohMoveHow,
          '1. Save a backup file here. Your browser keeps it with your other '
          'downloads.\n'
          '2. Go to the new address.\n'
          '3. Open the backup file there.');
      expect(ohMoveSaveLabel, 'Save a backup file');
      expect(ohMoveNothingDeleted,
          'Nothing here is deleted. Your records stay here until you remove '
          'them.');
      expect(ohMoveGoTo('stilllife.familyflourishing.org'),
          'Go to stilllife.familyflourishing.org');
    });
    test('offer', () {
      expect(ohMovedHereTitle, 'Used this app before at the old address?');
      expect(ohMovedHereBody,
          '1. Go to the old address and save a backup file there.\n'
          '2. Come back here and open it.');
      expect(ohMovedHereOldAddressLabel, 'Go to the old address');
      expect(ohMovedHereImportLabel, 'Open a backup file');
      expect(ohMovedHereDismissLabel, 'Not now');
    });
    test('plain words: curly apostrophes and no em dashes anywhere', () {
      final all = [
        ohMoveTitle('A'),
        ohMoveLivesAt('A', 'a.b'),
        ohMoveFound(0),
        ohMoveFound(1),
        ohMoveFound(2),
        ohMoveCounting,
        ohMoveCountFailed,
        ohMoveHow,
        ohMoveSaveLabel,
        ohMoveNothingDeleted,
        ohMoveGoTo('a.b'),
        ohMovedHereTitle,
        ohMovedHereBody,
        ohMovedHereOldAddressLabel,
        ohMovedHereImportLabel,
        ohMovedHereDismissLabel,
      ];
      for (final line in all) {
        expect(line.contains("'"), isFalse, reason: line);
        expect(line.contains('—'), isFalse, reason: line);
      }
    });
  });

  group('OhMoveDataScreen', () {
    late List<String> calls;
    late Completer<int> count;

    setUp(() => calls = []);

    Future<void> pump(WidgetTester tester,
        {double width = 360, double scale = 1}) async {
      // Made here, inside the test's fake-async zone: a completer made in
      // setUp completes on the real microtask queue, which pump never runs.
      count = Completer<int>();
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: OhTheme.light(),
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
        home: OhMoveDataScreen(
          appName: 'Still Life',
          newAddress: 'stilllife.familyflourishing.org',
          countRecords: () {
            calls.add('count');
            return count.future;
          },
          onSaveBackup: (_) async => calls.add('save'),
          onOpenLink: (uri) => calls.add('open $uri'),
        ),
      ));
    }

    testWidgets('says where the app lives now, and counts once',
        (tester) async {
      await pump(tester);
      expect(find.text('Still Life has moved'), findsOneWidget);
      expect(
          find.text('Still Life now lives at stilllife.familyflourishing.org.'),
          findsOneWidget);
      expect(find.text(ohMoveCounting), findsOneWidget);
      count.complete(12);
      await tester.pumpAndSettle();
      expect(find.text('We found 12 records saved in this browser.'),
          findsOneWidget);
      expect(find.text(ohMoveHow), findsOneWidget);
      expect(find.text(ohMoveNothingDeleted), findsOneWidget);
      expect(calls, ['count']);
    });

    testWidgets('a count that fails still offers the backup', (tester) async {
      await pump(tester);
      count.completeError(StateError('locked'));
      await tester.pumpAndSettle();
      expect(find.text(ohMoveCountFailed), findsOneWidget);
      expect(find.text(ohMoveSaveLabel), findsOneWidget);
    });

    testWidgets('the button calls the app’s own export, and the link opens '
        'the new address', (tester) async {
      await pump(tester);
      count.complete(3);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ohMoveSaveLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to stilllife.familyflourishing.org'));
      await tester.pumpAndSettle();
      expect(calls, [
        'count',
        'save',
        'open https://stilllife.familyflourishing.org/',
      ]);
    });

    testWidgets('it never calls a write: its only calls are the count, the '
        'export and the link', (tester) async {
      await pump(tester);
      count.complete(0);
      await tester.pumpAndSettle();
      // Tap every button on the screen.
      for (final button in tester.widgetList<ButtonStyleButton>(
          find.byWidgetPredicate((w) => w is ButtonStyleButton))) {
        button.onPressed?.call();
        await tester.pumpAndSettle();
      }
      expect(
          calls.toSet(),
          {'count', 'save', 'open https://stilllife.familyflourishing.org/'});
    });

    testWidgets('the button waits while a backup is being made',
        (tester) async {
      final saving = Completer<void>();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
        theme: OhTheme.light(),
        home: OhMoveDataScreen(
          appName: 'Still Life',
          newAddress: 'stilllife.familyflourishing.org',
          countRecords: () async => 1,
          onSaveBackup: (_) {
            saves++;
            return saving.future;
          },
          onOpenLink: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ohMoveSaveLabel));
      await tester.pump();
      await tester.tap(find.text(ohMoveSaveLabel), warnIfMissed: false);
      await tester.pump();
      expect(saves, 1);
      saving.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text(ohMoveSaveLabel));
      await tester.pump();
      expect(saves, 2);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at 320 dp x $scale with no overflow', (tester) async {
        await pump(tester, width: 320, scale: scale);
        count.complete(1234);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('OhMovedHereOffer', () {
    late List<String> calls;
    setUp(() => calls = []);

    Future<void> pump(WidgetTester tester,
        {required bool empty,
        bool web = true,
        double width = 360,
        double scale = 1}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: OhTheme.light(),
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
        home: Scaffold(
          body: ListView(children: [
            OhMovedHereOffer(
              storeIsEmpty: empty,
              appSlug: 'stilllife',
              onImport: (_) async => calls.add('import'),
              onWeb: web,
              onOpenLink: (uri) => calls.add('open $uri'),
            ),
            const Text('app content'),
          ]),
        ),
      ));
    }

    testWidgets('an empty store on the web shows the offer', (tester) async {
      await pump(tester, empty: true);
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      expect(find.text(ohMovedHereBody), findsOneWidget);
    });

    testWidgets('a store with data shows nothing', (tester) async {
      await pump(tester, empty: false);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    testWidgets('off the web it shows nothing', (tester) async {
      await pump(tester, empty: true, web: false);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    testWidgets('it links to the move page and to the app’s own import',
        (tester) async {
      await pump(tester, empty: true);
      await tester.tap(find.text(ohMovedHereOldAddressLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ohMovedHereImportLabel));
      await tester.pumpAndSettle();
      expect(calls, [
        'open https://levitatingflyfisher.github.io/move/stilllife/',
        'import',
      ]);
    });

    testWidgets('“Not now” hides it, and it stays hidden when the screen is '
        'built again', (tester) async {
      await pump(tester, empty: true);
      await tester.tap(find.text(ohMovedHereDismissLabel));
      await tester.pumpAndSettle();
      expect(find.text(ohMovedHereTitle), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, empty: true);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    test('it follows the platform by default', () {
      expect(
          OhMovedHereOffer(
                  storeIsEmpty: true, appSlug: 'x', onImport: (_) async {})
              .onWeb,
          isNull);
    });

    testWidgets('debugOhMovedHereOfferOnWeb lets an app test see it',
        (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      await tester.pumpWidget(MaterialApp(
        theme: OhTheme.light(),
        home: Scaffold(
          body: OhMovedHereOffer(
              storeIsEmpty: true, appSlug: 'x', onImport: (_) async {}),
        ),
      ));
      expect(find.text(ohMovedHereTitle), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at 320 dp x $scale with no overflow', (tester) async {
        await pump(tester, empty: true, width: 320, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
