import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/app/app.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// On the web the household's palette and choices live in the browser, and
/// clearing the browser's website data erases them. The family opens the app in a phone
/// browser, so the real [MantleApp] must say so above every screen on the
/// web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // As in the smoke test: resolve the theme without secure storage.
          themePreferenceProvider
              .overrideWith((ref) async => ThemePreference.light),
        ],
        child: const MantleApp(),
      ),
    );
    await tester.pumpAndSettle();
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
