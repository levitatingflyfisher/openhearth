import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/features/loans/domain/entities/loan.dart';
import 'package:still_life/features/loans/presentation/widgets/loan_status_card.dart';

import '../../../helpers/text_fit.dart';

/// Regression: at 3x text the "Mark Returned" label wrapped and its first
/// letters sat against the button's rounded left edge. Material shrinks a
/// filled button's side padding from 24 to 4 as text grows, and the label
/// was start-aligned.
Loan _loan() => Loan(
  id: 'l1',
  itemId: 'i1',
  itemName: 'Camera',
  borrowerName: 'Alice',
  expectedReturnDate: DateTime(2026, 1, 25),
  createdAt: DateTime(2025),
  modifiedAt: DateTime(2025),
);

void main() {
  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 3.0]) {
      testWidgets(
        '"Mark Returned" keeps clear of its button edges at $width wide, '
        '${scale}x',
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
                    child: LoanStatusCard(
                      loan: _loan(),
                      onMarkReturned: () {},
                      onEdit: () {},
                      onLend: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final button = tester.getRect(find.byType(FilledButton));
          final label = find.descendant(
            of: find.byType(FilledButton),
            matching: find.text('Mark Returned'),
          );
          final (left, right) = inkExtent(
            paragraphsUnder(tester, label).single,
          );
          expect(left - button.left, greaterThanOrEqualTo(16),
              reason: 'label crowds the left edge');
          expect(button.right - right, greaterThanOrEqualTo(16),
              reason: 'label crowds the right edge');
          expectAllTextReadable(tester, find.byType(FilledButton));
        },
      );
    }
  }
}
