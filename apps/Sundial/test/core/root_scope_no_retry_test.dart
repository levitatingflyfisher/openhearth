import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/providers/retry_policy.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/export/presentation/export_screen.dart';

/// A key store whose read fails the way a locked keychain does: with an
/// Exception (riverpod 3 retries Exceptions, not Errors).
class _LockedStore extends InMemorySecureKeyStore {
  int reads = 0;
  @override
  Future<String?> readMnemonic() async {
    reads++;
    throw Exception('keystore locked');
  }
}

/// The shared backup packages build against riverpod 2 and 3, so they cannot
/// name a retry policy; the app's root scope sets one for them. Riverpod 3
/// would otherwise retry the identity read up to 10 times while Export shows
/// "Checking backup status…" where its error and Try again belong. This pins
/// that the scope main() builds does not retry.
void main() {
  testWidgets('a failed backup status read is not retried by the root scope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = _LockedStore();
    await tester.pumpWidget(sundialProviderScope(
      overrides: [
        appDatabaseProvider
            .overrideWith((_) => AppDatabase(NativeDatabase.memory())),
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureKeyStoreProvider.overrideWithValue(store),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        sanctuaryAppDomainProvider.overrideWithValue('sundial'),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'sundial',
            aadContext: 'sundial-backup/v1',
            appDisplayName: 'Sundial',
          ),
        ),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      ],
      child: const MaterialApp(home: ExportScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);

    // Long enough for several of riverpod 3's default retries.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(store.reads, 1, reason: 'the keychain is read once, not in a loop');
    expect(find.text('Try again'), findsOneWidget,
        reason: 'the error stays on screen, not a spinner');
    expect(find.text('Checking backup status…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
