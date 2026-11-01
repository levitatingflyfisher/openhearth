import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/features/about/presentation/about_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// board-0166, board-0170: the household sees who publishes the app, in the
// fleet's one shared line (the words live in openhearth_design).
void main() {
  testWidgets('About names the publisher', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AboutScreen()));

    await tester.scrollUntilVisible(find.text(ohPublisherLine), 200,
        scrollable: find.byType(Scrollable).last);

    expect(find.text('Published by Intergenerational Symbolic Systems'),
        findsOneWidget);
    expect(find.byType(OhPublisherLine), findsOneWidget);
  });
}
