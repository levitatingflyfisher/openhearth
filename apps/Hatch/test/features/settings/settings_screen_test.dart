import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/settings/presentation/settings_screen.dart';
import 'package:hatch/shared/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
      cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
      sanctuaryAppDomainProvider.overrideWithValue('hatch'),
      sanctuaryBackupConfigProvider.overrideWithValue(
        const SanctuaryBackupConfig(
          appId: 'hatch',
          aadContext: 'hatch-backup/v1',
          appDisplayName: 'Hatch',
        ),
      ),
      backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return container;
}

Future<void> pumpSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sound toggle persists the mute flag to the settings table', (
    tester,
  ) async {
    final container = await makeContainer();
    await pumpSettings(tester, container);

    final soundTile = find.widgetWithText(SwitchListTile, 'Sound');
    expect(soundTile, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(soundTile).value,
      isTrue,
      reason: 'sound defaults to on',
    );

    await tester.tap(soundTile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(soundTile).value, isFalse);
    // Assert against the table directly: awaiting a fresh drift watch
    // stream's first emission deadlocks under the widget-test FakeAsync
    // zone (its initial fetch rides a timer nothing pumps).
    final db = container.read(appDatabaseProvider);
    final row = await db.select(db.settings).getSingle();
    expect(
      row.value,
      '1',
      reason: 'the flag must be in the database, not widget state',
    );
  });

  testWidgets('backup section renders its fleet tiles', (tester) async {
    final container = await makeContainer();
    await pumpSettings(tester, container);

    expect(find.text('Encrypted Backup'), findsOneWidget);
    expect(find.text('Restore from backup'), findsOneWidget);
    expect(find.text('Export as plain JSON'), findsOneWidget);
  });

  testWidgets('backup section says Android may back up to Google', (
    tester,
  ) async {
    final container = await makeContainer();
    await pumpSettings(tester, container);

    expect(
      find.text(
        'Android may also back up this app\u2019s data to Google, if the '
        'phone\u2019s owner allows it in Android settings. The encrypted '
        'backup here is the private choice.',
      ),
      findsOneWidget,
    );
  });

  // The fleet's one publisher line. Hatch has no About screen, so it sits at
  // the foot of the parent-facing Settings, as in the other fleet apps.
  testWidgets('the foot of Settings names the publisher', (tester) async {
    final container = await makeContainer();
    await pumpSettings(tester, container);

    await tester.scrollUntilVisible(
      find.text(ohPublisherLine),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Published by Intergenerational Symbolic Systems'),
      findsOneWidget,
    );
    expect(find.byType(OhPublisherLine), findsOneWidget);
  });
}
