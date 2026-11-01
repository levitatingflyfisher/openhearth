import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/app/app.dart';
import 'package:still_life/app/router.dart';
import 'package:still_life/core/providers/bootstrap_provider.dart';

/// On the web the household's inventory lives in the browser, and clearing
/// the browser's website data erases it. The family opens the app in a
/// phone browser, so the real [StillLifeApp] must say so above every screen
/// on the web, and say nothing off it.
void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The real app frame with one trivial screen: no database work.
          bootstrapProvider.overrideWith((ref) async {}),
          routerProvider.overrideWithValue(
            GoRouter(
              routes: [
                GoRoute(path: '/', builder: (_, _) => const SizedBox()),
              ],
            ),
          ),
        ],
        child: const StillLifeApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on the web the app shows the data notice once', (
    tester,
  ) async {
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
