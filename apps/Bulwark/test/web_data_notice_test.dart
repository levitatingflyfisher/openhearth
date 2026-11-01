import 'package:bulwark/core/providers/core_providers.dart';
import 'package:bulwark/core/storage/app_database.dart' hide UserPrefs;
import 'package:bulwark/features/sanctuary_backup/backup_config.dart';
import 'package:bulwark/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:bulwark/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On the web the household's records live in the browser, and clearing the
/// browser's website data erases them. The family opens the app in a phone
/// browser, so the real [BulwarkApp] must say so above every screen on the
/// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  /// Pumps the real app, counts the notice, then tears the app down and lets
  /// straggler timers expire (as the startup maintenance test does).
  Future<int> noticesShown(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((ref) => db),
          secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
          cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
          vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
          sanctuaryBackupConfigProvider.overrideWithValue(bulwarkBackupConfig),
          sanctuaryAppDomainProvider.overrideWithValue('bulwark'),
          backupSerializerProvider
              .overrideWith((ref) => BulwarkBackupSerializer(db)),
        ],
        child: const BulwarkApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final shown = find.text(ohWebDataNotice).evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    return shown;
  }

  testWidgets('on the web the app shows the data notice once',
      (tester) async {
    debugOhWebDataNoticeOnWeb = true;
    expect(await noticesShown(tester), 1);
  });

  testWidgets('off the web the app shows no data notice', (tester) async {
    debugOhWebDataNoticeOnWeb = false;
    expect(await noticesShown(tester), 0);
  });
}
