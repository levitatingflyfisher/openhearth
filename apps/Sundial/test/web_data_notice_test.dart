import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/router/app_router.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/sanctuary_backup/backup_config.dart';
import 'package:sundial/main.dart';

/// On the web the household's sessions live in the browser, and clearing the
/// browser's website data erases them. The family opens the app in a phone
/// browser, so the real [SundialApp] must say so above every screen on the
/// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  /// Pumps the real app, counts the notice, then unmounts the app and
  /// closes the database before any expectation runs (the drain the other
  /// Sundial tests use: closing drift under a live tree hangs the test).
  Future<int> noticesShown(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appRouterProvider.overrideWith(
          (ref) => GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const SizedBox()),
          ]),
        ),
        appDatabaseProvider.overrideWithValue(db),
        sanctuaryAppDomainProvider.overrideWithValue('sundial'),
        sanctuaryBackupConfigProvider.overrideWithValue(sundialBackupConfig),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      ],
      child: const SundialApp(),
    ));
    await tester.pump();
    final shown = find.text(ohWebDataNotice).evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
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
