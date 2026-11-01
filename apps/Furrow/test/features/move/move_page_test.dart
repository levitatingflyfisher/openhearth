import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/features/move/move_page.dart';
import 'package:furrow/features/sanctuary_backup/backup_config.dart';
import 'package:furrow/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:furrow/main.dart';
import 'package:furrow/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The web app moves to furrow.familyflourishing.org (owner ruling, 15 Nov
// 2026). The move page build, at the old origin, opens straight to the move
// screen and writes nothing. The new site offers the way back while the
// browser holds no records.
void main() {
  tearDown(debugResetOhMovedHereOffer);

  Uint8List payload(int records) => Uint8List.fromList(utf8.encode(jsonEncode({
        'app': 'furrow',
        'schemaVersion': 1,
        'payload': {'diaryEntries': List.filled(records, <String, Object>{})},
      })));

  test('the addresses', () {
    expect(moveAppSlug, 'furrow');
    expect(moveNewAddress, 'furrow.familyflourishing.org');
  });

  test('the seeded awards are not counted as the family’s records', () async {
    final seededOnly = FakeBackupSerializer(Uint8List.fromList(utf8.encode(
        jsonEncode({
      'app': 'furrow',
      'tables': {
        'habitBadges': List.filled(6, <String, Object>{}),
        'habits': <Object>[],
      },
    }))));
    expect(await countBackupRecords(seededOnly), 0);
    final withHabit = FakeBackupSerializer(Uint8List.fromList(utf8.encode(
        jsonEncode({
      'app': 'furrow',
      'tables': {
        'habitBadges': List.filled(6, <String, Object>{}),
        'habits': [<String, Object>{}],
      },
    }))));
    expect(await countBackupRecords(withHabit), 1);
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

  testWidgets('the move page build opens straight to the move screen, '
      'counts the records, and writes nothing', (tester) async {
    final serializer = FakeBackupSerializer(payload(3));
    final vault = InMemoryVaultStore();
    final keys = InMemorySecureKeyStore();
    await tester.pumpWidget(MovePageApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      overrides: [
        sanctuaryBackupConfigProvider.overrideWithValue(furrowBackupConfig),
        backupSerializerProvider.overrideWithValue(serializer),
        vaultStoreProvider.overrideWithValue(vault),
        sanctuary.secureKeyStoreProvider.overrideWithValue(keys),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OhMoveDataScreen), findsOneWidget);
    expect(find.byType(FurrowApp), findsNothing);
    expect(find.text('Furrow now lives at furrow.familyflourishing.org.'),
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
          theme: AppTheme.light,
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

    testWidgets('the real app shows it on onboarding, its first screen, when the store is empty',
        (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((ref) => db),
          sanctuary.secureKeyStoreProvider
              .overrideWithValue(InMemorySecureKeyStore()),
          sanctuary.cryptoServiceProvider
              .overrideWithValue(FakeCryptoService()),
          vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
          sanctuaryBackupConfigProvider.overrideWithValue(furrowBackupConfig),
          sanctuary.sanctuaryAppDomainProvider.overrideWithValue('furrow'),
          backupSerializerProvider
              .overrideWith((ref) => FurrowBackupSerializer(db)),
        ],
        child: const FurrowApp(),
      ));
      // Drift answers on real time: let it, between frames.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    });
  });
}
