import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/core/providers/database_provider.dart';
import 'package:lilt/core/providers/settings_providers.dart';
import 'package:lilt/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:lilt/features/settings/settings_screen.dart';
import 'package:lilt/services/database/database.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Recently cleared is the only way to restore sessions that Clear all
// sessions set aside. A failed read of it says so, with Try again; it is
// never drawn as nothing cleared, which reads "they are gone for good".
void main() {
  testWidgets('a failed read of cleared sessions is said, never missing',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var failing = true;
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
      backupSerializerProvider.overrideWith((ref) => LiltBackupSerializer(db)),
      clearedSessionsProvider.overrideWith((ref) async {
        if (failing) throw Exception('disk read failed');
        return const [];
      }),
    ]);
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Couldn’t read your cleared sessions'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
  });
}
