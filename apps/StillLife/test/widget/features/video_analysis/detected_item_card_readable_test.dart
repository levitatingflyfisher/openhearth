import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/features/video_analysis/domain/entities/detected_object.dart';
import 'package:still_life/features/video_analysis/presentation/widgets/detected_item_card.dart';

import '../../helpers/text_fit.dart';

/// Regression: with the app's real theme the card cut off its own words.
/// On a 320 wide phone at 1x it showed "Sony A7III Ca..." and "El..."; at
/// 3x it showed "Son...", "Digit / al" and a chip with no text, because a
/// fixed right column (price, confidence, actions) took the width the
/// title, tag and description needed.
DetectedObject _object() => DetectedObject(
  id: 'obj-1',
  label: 'Camera',
  confidence: 0.95,
  frameImage: Uint8List(1),
  frameIndex: 0,
  enhancedName: 'Sony A7III Camera',
  brand: 'Sony',
  model: 'A7III',
  description: 'Digital mirrorless camera',
  estimatedPrice: 1299.99,
  category: 'Electronics',
);

void main() {
  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 3.0]) {
      testWidgets(
        'DetectedItemCard shows every word whole at $width wide, ${scale}x',
        (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = Size(width, 740);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: OhTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: DetectedItemCard(
                      object: _object(),
                      onConfirm: () {},
                      onEdit: () {},
                      onDelete: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          for (final s in const [
            'Sony A7III Camera',
            'Electronics',
            'Sony A7III',
            'Digital mirrorless camera',
            r'$1300',
            '95%',
          ]) {
            expect(find.text(s), findsOneWidget, reason: s);
          }
          expectAllTextReadable(tester, find.byType(DetectedItemCard));
        },
      );
    }
  }
}
