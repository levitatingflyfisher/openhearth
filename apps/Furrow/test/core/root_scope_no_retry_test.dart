import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/retry_policy.dart';
import 'package:furrow/features/sanctuary_backup/presentation/backup_section.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

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
/// would otherwise read a locked keychain up to 10 times on its own, with
/// "Checking backup status…" where the error and Try again belong. This pins
/// that the scope main() builds does not retry.
void main() {
  testWidgets('a failed keychain read is not retried by the root scope',
      (tester) async {
    final store = _LockedStore();
    await tester.pumpWidget(
      furrowProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
          secureKeyStoreProvider.overrideWithValue(store),
          cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
          sanctuaryAppDomainProvider.overrideWithValue('furrow'),
          sanctuaryBackupConfigProvider.overrideWithValue(
            const SanctuaryBackupConfig(
              appId: 'furrow',
              aadContext: 'furrow-backup/v1',
              appDisplayName: 'Furrow',
            ),
          ),
          backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        ],
        child: MaterialApp(
          home: Scaffold(body: ListView(children: const [BackupSection()])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(store.reads, 1);

    // Long enough for several of riverpod 3's default retries.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(store.reads, 1, reason: 'the keychain is read once, not in a loop');
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
