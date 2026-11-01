import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:reckon/app/app.dart';
import 'package:reckon/core/auth/auth_providers.dart';
import 'package:reckon/core/database/app_database.dart';
import 'package:reckon/core/database/database_providers.dart';
import 'package:reckon/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

/// On the web the household's decisions live in the browser, and clearing
/// the browser's website data erases them. The family opens the app in a
/// phone browser, so the real [ReckonApp] must say so above every screen on
/// the web, and say nothing off it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<void> pumpApp(WidgetTester tester) async {
    // As in startup_maintenance_test: no notification launch, no stored
    // theme.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    // Not closed in teardown: closing drift inside the FakeAsync zone
    // deadlocks (see startup_maintenance_test).
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          onboardingCompleteProvider.overrideWith((ref) async => true),
          secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
          cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
          sanctuaryAppDomainProvider.overrideWithValue('reckon'),
          vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
          backupSerializerProvider
              .overrideWith((ref) => ReckonBackupSerializer(db)),
          sanctuaryBackupConfigProvider.overrideWithValue(
            const SanctuaryBackupConfig(
              appId: 'reckon',
              aadContext: 'reckon-backup/v1',
              appDisplayName: 'Reckon',
            ),
          ),
        ],
        child: const ReckonApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('on the web the app shows the data notice once',
      (tester) async {
    debugOhWebDataNoticeOnWeb = true;
    await pumpApp(tester);
    expect(find.text(ohWebDataNotice), findsOneWidget);
  });

  testWidgets('off the web the app shows no data notice', (tester) async {
    debugOhWebDataNoticeOnWeb = false;
    await pumpApp(tester);
    expect(find.text(ohWebDataNotice), findsNothing);
  });
}
