import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/features/inventory/domain/entities/tag.dart';
import 'package:still_life/features/inventory/presentation/widgets/tag_chip.dart';

import '../../../helpers/text_fit.dart';

/// Regression: a chip label is one line by default, so at 3x text a long
/// tag name ("Long Tag Name That Could Wrap") faded out at the chip's edge
/// on a narrow phone. The chip must stay inside the screen and show the
/// whole name.
Tag _tag(String name) => Tag(
  id: 'tag-5',
  name: name,
  color: 0xFF9C27B0,
  createdAt: DateTime(2025),
  modifiedAt: DateTime(2025),
);

void main() {
  for (final width in const [320.0, 360.0]) {
    for (final deletable in const [false, true]) {
      testWidgets(
        'a long TagChip fits a $width wide screen at 3x and shows its whole '
        'name (deletable: $deletable)',
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
                ).copyWith(textScaler: const TextScaler.linear(3.0)),
                child: child!,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      children: [
                        TagChip(
                          tag: _tag('Long Tag Name That Could Wrap'),
                          onTap: () {},
                          onDeleted: deletable ? () {} : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final chip = tester.getRect(find.byType(TagChip));
          expect(chip.left, greaterThanOrEqualTo(8));
          expect(chip.right, lessThanOrEqualTo(width - 8));
          expectAllTextReadable(tester, find.byType(TagChip));
        },
      );
    }
  }
}
