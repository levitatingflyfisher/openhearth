import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/app/app.dart';
import 'package:lullaby/app/theme/theme.dart';
import 'package:lullaby/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:lullaby/features/move/move_page.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

const _config = SanctuaryBackupConfig(
  appId: 'lullaby',
  aadContext: 'ghost-backup/v1',
  appDisplayName: 'Lullaby',
);

// The web app moves to its own address (owner ruling, 15 Nov 2026). The
// move page build, at the old origin, opens straight to the move screen and
// writes nothing. The new site offers the way back while the browser holds
// no records.
void main() {
  tearDown(debugResetOhMovedHereOffer);

  Uint8List payload(int records) => Uint8List.fromList(utf8.encode(jsonEncode({
        'app': 'lullaby',
        'schemaVersion': 1,
        'tables': {'babies': List.filled(records, <String, Object>{})},
      })));

  test('the addresses', () {
    expect(moveAppSlug, 'lullaby');
    expect(moveNewAddress, 'lullaby.familyflourishing.org');
  });

  test('the move page flag is off in a normal build', () {
    expect(ohMovePage, isFalse);
  });

  test('main opens the move page before anything else runs', () {
    final source = File('lib/main.dart').readAsStringSync();
    final body = source.substring(source.indexOf('Future<void> main()'));
    final moveAt = body.indexOf('if (ohMovePage)');
    expect(moveAt, isNonNegative);
    expect(
        body
            .substring(0, moveAt)
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .replaceAll(RegExp(r'\s+'), ''),
        'Future<void>main()async{WidgetsFlutterBinding.ensureInitialized();');
  });

  testWidgets('the move page build opens straight to the move screen, '
      'counts the records, and writes nothing', (tester) async {
    final serializer = FakeBackupSerializer(payload(3));
    final vault = InMemoryVaultStore();
    final keys = InMemorySecureKeyStore();
    await tester.pumpWidget(MovePageApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      overrides: [
        sanctuaryBackupConfigProvider.overrideWithValue(_config),
        backupSerializerProvider.overrideWithValue(serializer),
        vaultStoreProvider.overrideWithValue(vault),
        sanctuary.secureKeyStoreProvider.overrideWithValue(keys),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OhMoveDataScreen), findsOneWidget);
    expect(find.byType(LullabyApp), findsNothing);
    expect(find.text('Lullaby now lives at lullaby.familyflourishing.org.'),
        findsOneWidget);
    expect(find.text('We found 3 records saved in this browser.'),
        findsOneWidget);
    expect(serializer.restored, isNull);
    expect(await vault.list(), isEmpty);
    expect(await keys.readMnemonic(), isNull);
  });

  group('the offer on the first screen', () {
    Future<void> pumpSlot(WidgetTester tester,
        {required int records, required bool web}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          backupSerializerProvider
              .overrideWithValue(FakeBackupSerializer(payload(records))),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: MovedHereOfferSlot(onWeb: web)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an empty browser on the web shows it', (tester) async {
      await pumpSlot(tester, records: 0, web: true);
      expect(find.text(ohMovedHereTitle), findsOneWidget);
    });

    testWidgets('a browser with records shows nothing', (tester) async {
      await pumpSlot(tester, records: 2, web: true);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    testWidgets('off the web it shows nothing', (tester) async {
      await pumpSlot(tester, records: 0, web: false);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    testWidgets('the dashboard with no baby, the first screen, shows it '
        'when the store is empty', (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeBabyProvider.overrideWith((ref) => Stream.value(null)),
          backupSerializerProvider
              .overrideWithValue(FakeBackupSerializer(payload(0))),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      expect(find.text('Welcome to Lullaby!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
