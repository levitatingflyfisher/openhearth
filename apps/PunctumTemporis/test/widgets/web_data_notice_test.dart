// On the web the household's clips and journal live in the browser, and
// clearing the browser's website data erases them. The family opens the app
// in a phone browser, so the real OneSecondApp must say so above every
// screen on the web, and say nothing off it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.base);
  final String base;
  @override
  Future<String?> getApplicationDocumentsPath() async => base;
  @override
  Future<String?> getApplicationSupportPath() async => base;
  @override
  Future<String?> getTemporaryPath() async => '$base/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_web_notice_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    debugOhWebDataNoticeOnWeb = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Pumps the real app as startup_freshness_test does (real event loop for
  /// the startup file work) and counts the notice.
  Future<int> noticesShown(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 1});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await tester.runAsync(() async {
      await tester.pumpWidget(OneSecondApp(
        storageService: storage,
        backupServiceFactory: () => BackupService(storage,
            vault: BackupVault(InMemoryVaultStore(),
                appId: 'punctum', extension: 'json'),
            prefs: prefs),
      ));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    return find.text(ohWebDataNotice).evaluate().length;
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
