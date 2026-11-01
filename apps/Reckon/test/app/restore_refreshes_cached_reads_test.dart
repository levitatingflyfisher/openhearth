import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/app/root_overrides.dart';
import 'package:reckon/core/database/app_database.dart';
import 'package:reckon/core/database/database_providers.dart';
import 'package:reckon/features/case/data/case_providers.dart';
import 'package:reckon/features/record/data/record_providers.dart';
import 'package:reckon/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

/// A restore replaces every decision on the phone. The cached reads the
/// Record and decision screens hold must show the restored data, not the
/// rows the restore removed. This drives Reckon's real restore wiring (the
/// app's own `onAfterRestore`) while the reads are being listened to, as
/// they are while those screens are open.
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

Future<void> _closedCase(AppDatabase db, String id, String question) =>
    db.into(db.cases).insert(CasesCompanion.insert(
          id: id,
          createdAt: DateTime.utc(2026, 6, 1),
          status: 'closed',
          question: question,
          optionA: 'A',
          optionB: 'B',
          statedCriteria: const [],
          stakes: 'low',
          regretHorizon: 'weeks',
        ));

ProviderContainer _container(AppDatabase db, SecureKeyStore store) {
  // The app's own backup config, onAfterRestore included.
  final root = ProviderContainer(overrides: reckonRootOverrides(web: false));
  final config = root.read(sanctuaryBackupConfigProvider);
  root.dispose();

  final c = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    secureKeyStoreProvider.overrideWithValue(store),
    cryptoServiceProvider.overrideWithValue(const DefaultCryptoService()),
    sanctuaryAppDomainProvider.overrideWithValue('reckon'),
    vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
    backupSerializerProvider.overrideWith((ref) => ReckonBackupSerializer(db)),
    sanctuaryBackupConfigProvider.overrideWithValue(config),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('after a restore the record and a decision show the restored data',
      () async {
    final from = AppDatabase(NativeDatabase.memory());
    addTearDown(from.close);
    await _closedCase(from, 'new', 'Restored decision');
    final backup = await _container(
      from,
      InMemorySecureKeyStore(mnemonic: _phrase, acknowledged: true),
    ).read(backupControllerProvider.notifier).exportBackup();
    expect(backup, isNotNull);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _closedCase(db, 'old', 'Decision the restore removes');
    final c = _container(db, InMemorySecureKeyStore());

    // The screens' reads, held open as an open screen holds them.
    c.listen(closedCasesProvider, (_, _) {});
    c.listen(caseByIdProvider('old'), (_, _) {});
    c.listen(backupControllerProvider, (_, _) {});
    expect((await c.read(closedCasesProvider.future)).map((x) => x.question),
        ['Decision the restore removes']);
    expect(await c.read(caseByIdProvider('old').future), isNotNull);

    final outcome = await c
        .read(backupControllerProvider.notifier)
        .restoreWithPhrase(backup!.bytes, _phrase);
    expect(outcome, RestoreOutcome.success);

    expect((await c.read(closedCasesProvider.future)).map((x) => x.question),
        ['Restored decision']);
    expect(await c.read(caseByIdProvider('old').future), isNull);
  });
}
