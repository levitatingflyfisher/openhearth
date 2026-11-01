import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:still_life/app/app.dart';
import 'package:still_life/core/providers/profile_providers.dart';
import 'package:still_life/features/move/move_page.dart';
import 'package:still_life/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:still_life/features/profiles/domain/entities/profile.dart';

import '../../../mocks/fake_profile_repository.dart';

const _config = SanctuaryBackupConfig(
  appId: 'stilllife',
  aadContext: 'stilllife-backup/v1',
  appDisplayName: 'Still Life',
);

/// In-memory stub for [ActiveProfileNotifier]: no secure storage calls.
class _FakeActiveProfileNotifier extends ActiveProfileNotifier {
  @override
  Future<Profile?> build() async => null;
}

// The web app moves to stilllife.familyflourishing.org (owner ruling, 15 Nov
// 2026). The move page build, at the old origin, opens straight to the move
// screen and writes nothing. The new site offers the way back while the
// browser holds no records.
void main() {
  tearDown(debugResetOhMovedHereOffer);

  Uint8List payload(int records) => Uint8List.fromList(utf8.encode(jsonEncode({
        'app': 'stilllife',
        'schemaVersion': 1,
        'data': {'items': List.filled(records, <String, Object>{})},
      })));

  test('the addresses', () {
    expect(moveAppSlug, 'stilllife');
    expect(moveNewAddress, 'stilllife.familyflourishing.org');
  });

  test('the seeded Consumables category is not counted as the family’s '
      'records', () async {
    final seededOnly = FakeBackupSerializer(Uint8List.fromList(utf8.encode(
        jsonEncode({
      'app': 'still_life',
      'data': {
        'categories': [<String, Object>{}],
        'items': <Object>[],
      },
    }))));
    expect(await countBackupRecords(seededOnly), 0);
    final withItem = FakeBackupSerializer(Uint8List.fromList(utf8.encode(
        jsonEncode({
      'app': 'still_life',
      'data': {
        'categories': [<String, Object>{}],
        'items': [<String, Object>{}],
      },
    }))));
    expect(await countBackupRecords(withItem), 1);
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
      theme: OhTheme.light(),
      darkTheme: OhTheme.hearthDark(),
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
    expect(find.byType(StillLifeApp), findsNothing);
    expect(find.text('Still Life now lives at stilllife.familyflourishing.org.'),
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
          theme: OhTheme.light(),
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

    testWidgets('onboarding, the first screen, shows it when the store is '
        'empty, with no overflow', (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          activeProfileProvider.overrideWith(_FakeActiveProfileNotifier.new),
          backupSerializerProvider
              .overrideWithValue(FakeBackupSerializer(payload(0))),
        ],
        child: MaterialApp(
          theme: OhTheme.light(),
          home: const OnboardingScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
