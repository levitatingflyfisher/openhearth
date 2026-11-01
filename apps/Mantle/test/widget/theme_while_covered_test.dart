// test/widget/theme_while_covered_test.dart
//
// A theme picked in Settings applies at once, while Settings covers Home,
// and Home's own toggle shows it on the way back. Riverpod 3 pauses what a
// hidden widget watches; this pins that the household still sees the new
// theme everywhere.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/app/app.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:mantle/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

void main() {
  late MantleDatabase db;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = MantleDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  testWidgets('a theme picked in Settings applies under it and on Home',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('mantle'),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'mantle',
            aadContext: 'mantle-backup/v1',
            appDisplayName: 'Mantle',
          ),
        ),
        backupSerializerProvider
            .overrideWith((ref) => MantleBackupSerializer(db)),
      ],
      child: const MantleApp(),
    ));
    await tester.pumpAndSettle();

    ThemeMode appMode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    OhThemeModePreference homeToggle() => tester
        .widget<OhThemeToggle>(find.byType(OhThemeToggle, skipOffstage: false))
        .value;

    expect(appMode(), ThemeMode.system);

    await tester.tap(find.byKey(const Key('home-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-theme-dark')));
    await tester.pumpAndSettle();

    // Settings is on top, Home is hidden under it: the app already shows Dark.
    expect(find.text('Appearance'), findsOneWidget);
    expect(appMode(), ThemeMode.dark);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsNothing);
    expect(homeToggle(), ThemePreference.dark.toggleValue);
  });
}
