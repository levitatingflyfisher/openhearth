import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hatch/core/engine/engine_providers.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/router/app_router.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/sanctuary_backup/backup_config.dart';
import 'package:hatch/main.dart';
import 'package:hatch/shared/audio/audio.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCuePlayer implements CuePlayer {
  @override
  Future<void> load(String assetPath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}

/// On the web a child's progress lives in the browser, and clearing the
/// browser's website data erases it. The family opens the app in a phone
/// browser, so the real [HatchApp] must say so above every screen on the
/// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<void> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appRouterProvider.overrideWith(
          (ref) => GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          ]),
        ),
        appDatabaseProvider.overrideWithValue(db),
        audioServiceProvider.overrideWith(
          (ref) => AudioService(
            isMuted: () => true,
            playerFactory: _FakeCuePlayer.new,
          ),
        ),
        sanctuaryAppDomainProvider.overrideWithValue('hatch'),
        sanctuaryBackupConfigProvider.overrideWithValue(hatchBackupConfig),
        backupSerializerProvider.overrideWithValue(FakeBackupSerializer()),
        secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
        vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      ],
      child: const HatchApp(),
    ));
    await tester.pump();
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
