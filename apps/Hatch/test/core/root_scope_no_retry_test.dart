import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/providers/retry_policy.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/settings/presentation/settings_screen.dart';
import 'package:hatch/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// would otherwise read a locked keychain up to 10 times on its own. This
/// pins that the scope main() builds does not retry.
void main() {
  testWidgets('a failed keychain read is not retried by the root scope', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = _LockedStore();
    await tester.pumpWidget(
      hatchProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureKeyStoreProvider.overrideWithValue(store),
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
        child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(store.reads, 1);

    // Long enough for several of riverpod 3's default retries.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(store.reads, 1, reason: 'the keychain is read once, not in a loop');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
