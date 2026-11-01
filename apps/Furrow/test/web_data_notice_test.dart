import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furrow/core/providers/core_providers.dart';
import 'package:furrow/core/storage/app_database.dart';
import 'package:furrow/main.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On the web the household's garden lives in the browser, and clearing the
/// browser's website data erases it. The family opens the app in a phone
/// browser, so the real [FurrowApp] must say so above every screen on the
/// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<void> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
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
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const FurrowApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
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
