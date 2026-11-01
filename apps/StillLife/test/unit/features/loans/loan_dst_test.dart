import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/features/loans/domain/entities/loan.dart';

// A local day is 23 hours long when the clocks go forward (8 March 2026 in
// the United States). Counting days as a wall-clock difference then comes up
// one short, so a loan four calendar days away read as "due soon". Under
// TZ=UTC this passes before the fix; under TZ=America/New_York it does not.
void main() {
  Loan loanDue(DateTime due) => Loan(
    id: 'l1',
    itemId: 'i1',
    itemName: 'Camera',
    borrowerName: 'Alice',
    expectedReturnDate: due,
    createdAt: DateTime(2026, 1, 1),
    modifiedAt: DateTime(2026, 1, 1),
  );

  test('four calendar days away across spring forward is not due soon', () {
    withClock(Clock.fixed(DateTime(2026, 3, 7)), () {
      expect(loanDue(DateTime(2026, 3, 11)).isDueSoon, isFalse);
    });
  });

  test('three calendar days away across spring forward is due soon', () {
    withClock(Clock.fixed(DateTime(2026, 3, 7)), () {
      expect(loanDue(DateTime(2026, 3, 10)).isDueSoon, isTrue);
    });
  });
}
