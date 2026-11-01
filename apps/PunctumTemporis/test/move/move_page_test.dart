// The web app moves to punctum.familyflourishing.org (owner ruling, 15 Nov
// 2026). The move page build, at the old origin, opens straight to the move
// screen, counts the clips, and offers the app's own backup with nothing
// that restores. The new site offers the way back while it holds no clips.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/move/move_page.dart';
import 'package:one_second_a_day/screens/backup_restore_screen.dart';
import 'package:one_second_a_day/screens/onboarding_screen.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A storage with [clips] clips in memory and no files behind it.
class _Storage extends StorageService {
  _Storage(super.prefs, this._count);
  final int _count;
  @override
  Map<String, List<Clip>> get clips => {
        for (var i = 0; i < _count; i++)
          '2026-11-${(i + 1).toString().padLeft(2, '0')}': [
            Clip.fromJson({
              'id': 'c$i',
              'date': '2026-11-${(i + 1).toString().padLeft(2, '0')}',
              'filePath': '/clips/c$i.mp4',
              'type': 'video',
              'createdAt': '2026-11-01T12:00:00.000',
            }),
          ],
      };
}

Future<StorageService> _storage(int clips) async {
  SharedPreferences.setMockInitialValues({'crt_effects': false});
  return _Storage(await SharedPreferences.getInstance(), clips);
}

void main() {
  tearDown(debugResetOhMovedHereOffer);
  setUp(() => AppTheme.visualStyle = 'hearth');

  test('the addresses', () {
    expect(moveAppSlug, 'punctum');
    expect(moveNewAddress, 'punctum.familyflourishing.org');
  });

  test('the move page flag is off in a normal build', () {
    expect(ohMovePage, isFalse);
  });

  test('main opens the move page before anything else runs', () {
    final source = File('lib/main.dart').readAsStringSync();
    final body = source.substring(source.indexOf('void main()'));
    final moveAt = body.indexOf('if (ohMovePage)');
    expect(moveAt, isNonNegative);
    expect(
        body
            .substring(0, moveAt)
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .replaceAll(RegExp(r'\s+'), ''),
        'voidmain()async{WidgetsFlutterBinding.ensureInitialized();');
  });

  test('the move page opens the journal read-only', () {
    final source = File('lib/main.dart').readAsStringSync();
    final branch = source.substring(source.indexOf('if (ohMovePage)'),
        source.indexOf('await SystemChrome'));
    expect(branch, contains('initialize(readOnly: true)'));
  });

  testWidgets('the move page build opens straight to the move screen and '
      'counts the clips', (tester) async {
    final storage = await _storage(3);
    await tester.pumpWidget(MovePageApp(storage: storage));
    await tester.pumpAndSettle();
    expect(find.byType(OhMoveDataScreen), findsOneWidget);
    expect(find.byType(OneSecondApp), findsNothing);
    expect(
        find.text('Punctum Temporis now lives at '
            'punctum.familyflourishing.org.'),
        findsOneWidget);
    expect(find.text('We found 3 records saved in this browser.'),
        findsOneWidget);
  });

  testWidgets('the export-only backup screen has nothing that restores',
      (tester) async {
    final storage = await _storage(1);
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      home: BackupRestoreScreen(
          storageService: storage,
          keyStore: InMemorySecureKeyStore(),
          exportOnly: true),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CREATE BACKUP'), findsOneWidget);
    expect(find.text('RESTORE BACKUP'), findsNothing);
    expect(find.text('PREVIOUS SNAPSHOTS'), findsNothing);
  });

  group('the offer on the first screen', () {
    Future<void> pumpOnboarding(WidgetTester tester, int clips) async {
      final storage = await _storage(clips);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.buildTheme(Brightness.light, Colors.green),
        home: OnboardingScreen(storageService: storage, onComplete: () {}),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('onboarding in an empty browser on the web shows it',
        (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      await pumpOnboarding(tester, 0);
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a browser with clips shows nothing', (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      await pumpOnboarding(tester, 2);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    testWidgets('off the web it shows nothing', (tester) async {
      debugOhMovedHereOfferOnWeb = false;
      await pumpOnboarding(tester, 0);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });
  });
}
