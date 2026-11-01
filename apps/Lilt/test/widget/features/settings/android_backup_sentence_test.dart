import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/core/providers/database_provider.dart';
import 'package:lilt/core/providers/settings_providers.dart';
import 'package:lilt/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:lilt/features/settings/settings_screen.dart';
import 'package:lilt/services/database/database.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _makeContainer() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureKeyStoreProvider.overrideWithValue(
      InMemorySecureKeyStore(
        mnemonic: 'abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon about',
        acknowledged: true,
        lastBackupAt: DateTime(2026, 7, 1),
      ),
    ),
    cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
    sanctuaryAppDomainProvider.overrideWithValue('lilt'),
    sanctuaryBackupConfigProvider.overrideWithValue(
      const SanctuaryBackupConfig(
        appId: 'lilt',
        aadContext: 'lilt-backup/v1',
        appDisplayName: 'Lilt',
      ),
    ),
    backupSerializerProvider.overrideWith(
      (ref) => LiltBackupSerializer(db),
    ),
  ]);
  return container;
}

/// Android may back up the app's data to Google when the phone's owner allows
/// it, so Settings says so beside Lilt's own encrypted backup (board-0125).
void main() {
  late ProviderContainer container;
  setUp(() async => container = await _makeContainer());
  tearDown(() => container.dispose());

  testWidgets('Settings says Android may back up to Google, beside the backup',
      (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    final sentence = find.text(
      'Android may also back up this app’s data to Google, if the '
      'phone’s owner allows it in Android settings. The encrypted backup '
      'here is the private choice.',
    );
    await tester.scrollUntilVisible(sentence, 200,
        scrollable: find.byType(Scrollable).first);
    expect(sentence, findsOneWidget);
  });

  // The fleet's one publisher line. Lilt has no About screen, so it sits at
  // the foot of Settings, under the version, as in the other fleet apps.
  testWidgets('the foot of Settings names the publisher', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text(ohPublisherLine), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Published by Intergenerational Symbolic Systems'),
        findsOneWidget);
    expect(find.byType(OhPublisherLine), findsOneWidget);
  });
}
