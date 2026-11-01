import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/features/loans/domain/entities/loan.dart';
import 'package:still_life/features/loans/presentation/controllers/loan_controller.dart';
import 'package:still_life/features/loans/presentation/screens/all_loans_screen.dart';

import '../../../helpers/text_fit.dart';

Loan _loan({
  String id = 'l1',
  String itemName = 'Camera',
  String borrower = 'Alice',
  DateTime? expectedReturnDate,
}) => Loan(
  id: id,
  itemId: 'i1',
  itemName: itemName,
  borrowerName: borrower,
  expectedReturnDate: expectedReturnDate,
  createdAt: DateTime(2025),
  modifiedAt: DateTime(2025),
);

Widget _wrap(List<Loan> loans) => ProviderScope(
  overrides: [
    activeLoansProvider.overrideWith((ref) => Stream.value(loans)),
    loanControllerProvider.overrideWith(() => _FakeCtrl()),
  ],
  child: const MaterialApp(home: AllLoansScreen()),
);

class _FakeCtrl extends LoanController {
  @override
  Future<void> build() async {}
  @override
  Future<void> markReturned(String id) async {}
}

void main() {
  testWidgets('shows empty state when no loans', (tester) async {
    await tester.pumpWidget(_wrap([]));
    await tester.pump();
    expect(find.text('No items on loan'), findsOneWidget);
  });

  testWidgets('shows item name and borrower', (tester) async {
    await tester.pumpWidget(_wrap([_loan()]));
    await tester.pump();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
  });

  testWidgets('groups overdue loans separately', (tester) async {
    final overdue = _loan(
      id: 'l2',
      expectedReturnDate: DateTime.now().subtract(const Duration(days: 2)),
    );
    final upcoming = _loan(id: 'l3');
    await tester.pumpWidget(_wrap([overdue, upcoming]));
    await tester.pump();
    expect(find.text('Overdue'), findsOneWidget); // section header
  });

  // Regression: at 3x text "No items on loan" wrapped to two lines that
  // started at the very left edge of the screen. The empty state had no
  // side padding (the page's own is off so the list rows can run full
  // width) and its text was left-aligned.
  for (final width in const [320.0, 360.0]) {
    testWidgets('empty state text is centred inside the 16 side gutter at '
        '$width wide, 3x', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLoansProvider.overrideWith((ref) => Stream.value([])),
            loanControllerProvider.overrideWith(() => _FakeCtrl()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.0)),
              child: child!,
            ),
            home: const AllLoansScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final p = paragraphsUnder(tester, find.text('No items on loan')).single;
      final (left, right) = inkExtent(p);
      expect(left, greaterThanOrEqualTo(16), reason: 'touches the left edge');
      expect(right, lessThanOrEqualTo(width - 16));
      // Centred: each line sits midway, so the ink's two margins match.
      expect((left - (width - right)).abs(), lessThan(2),
          reason: 'left margin $left, right margin ${width - right}');
    });
  }
}
