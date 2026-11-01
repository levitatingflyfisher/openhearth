import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/app/app.dart';
import 'package:lullaby/app/router.dart';
import 'package:lullaby/core/providers/database_provider.dart';
import 'package:lullaby/core/providers/sync_providers.dart';
import 'package:lullaby/features/settings/presentation/controllers/theme_controller.dart';
import 'package:lullaby/services/database/database.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

import '../../test_setup.dart';

/// On the web a baby's log lives in the browser, and clearing the browser's
/// website data erases it. The family opens the app in a phone browser, so
/// the real [LullabyApp] must say so above every screen on the web, and say
/// nothing off it.
void main() {
  ensureSqlite3();
  // One fresh in-memory database per test, never shared.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const homeWidget = MethodChannel('home_widget');

  setUp(() {
    // The app sets the home-screen widget's group at start; no plugin here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, (call) async => true);
  });

  tearDown(() {
    debugOhWebDataNoticeOnWeb = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, null);
  });

  /// Pumps the real app on Home, counts the notice, then unmounts and closes
  /// the database the way navigation_doors_test does.
  Future<int> noticesShown(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime(2026, 1, 1);
    await tester.runAsync(() => db.babyDao.insertBaby(BabiesCompanion.insert(
          id: 'b1',
          name: 'Nora',
          dateOfBirth: DateTime(2025, 11, 1),
          createdAt: now,
          modifiedAt: now,
        )));
    router.go('/dashboard');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        themeStorageProvider.overrideWithValue(InMemorySecretStorage()),
        syncSettingsStorageProvider.overrideWithValue(InMemorySecretStorage()),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        cryptoServiceProvider.overrideWithValue(FakeCryptoService()),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
        sanctuaryBackupConfigProvider.overrideWithValue(
          const SanctuaryBackupConfig(
            appId: 'lullaby',
            aadContext: 'ghost-backup/v1',
            appDisplayName: 'Lullaby',
          ),
        ),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
      ],
      child: const LullabyApp(),
    ));
    await tester.pumpAndSettle();
    // Let the start-up home-widget refresh (real database reads) finish
    // before the app is unmounted, or it reads a disposed container.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final shown = find.text(ohWebDataNotice).evaluate().length;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    unawaited(db.close());
    await tester.pump(const Duration(milliseconds: 1));
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
