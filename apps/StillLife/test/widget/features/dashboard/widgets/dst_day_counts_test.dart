import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/features/dashboard/presentation/widgets/upcoming_maintenance_widget.dart';
import 'package:still_life/features/dashboard/presentation/widgets/warranty_expiry_widget.dart';
import 'package:still_life/features/maintenance/domain/entities/maintenance_log.dart';
import 'package:still_life/features/maintenance/presentation/controllers/maintenance_controller.dart';
import 'package:still_life/features/maintenance/presentation/screens/maintenance_screen.dart';
import 'package:still_life/services/database/database.dart' show Item;

// The clocks go forward on 8 March 2026 (United States), so the week from 7
// to 15 March is 191 hours long and a wall-clock difference counts 7 days,
// not 8. Under TZ=UTC these pass before the fix; under TZ=America/New_York
// they do not.
void main() {
  final today = DateTime(2026, 3, 7);
  final stamp = DateTime(2026, 1, 1);

  Item itemExpiring(DateTime expiry) => Item(
    id: 'item1',
    name: 'Laptop',
    description: '',
    categoryId: 'cat1',
    roomId: 'room1',
    purchaseDate: null,
    purchasePriceCents: null,
    currentValueCents: null,
    replacementCostCents: null,
    condition: null,
    serialNumber: null,
    warrantyExpiration: expiry,
    barcode: null,
    storeUrl: null,
    notes: null,
    isInsured: false,
    createdAt: stamp,
    modifiedAt: stamp,
    nodeId: '',
    hlc: '',
    isDeleted: false,
  );

  MaintenanceLog logDue(DateTime due) => MaintenanceLog(
    id: 'log1',
    title: 'Boiler',
    performedAt: stamp,
    nextDueAt: due,
    createdAt: stamp,
    modifiedAt: stamp,
  );

  testWidgets('warranty chip counts calendar days across spring forward', (
    tester,
  ) async {
    await withClock(Clock.fixed(today), () async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            warrantyExpiringSoonProvider.overrideWith(
              (_) async => [itemExpiring(DateTime(2026, 3, 15))],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: WarrantyExpiryWidget()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    expect(find.text('8 days'), findsOneWidget);
  });

  testWidgets('dashboard maintenance chip is green 31 calendar days out', (
    tester,
  ) async {
    await withClock(Clock.fixed(today), () async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            upcomingMaintenanceProvider.overrideWith(
              (_) async => [logDue(DateTime(2026, 4, 7))],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UpcomingMaintenanceWidget()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, OhColors.sage600);
  });

  testWidgets('maintenance log chip is green 31 calendar days out', (
    tester,
  ) async {
    await withClock(Clock.fixed(today), () async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            maintenanceLogsProvider.overrideWith(
              (_) => Stream.value([logDue(DateTime(2026, 4, 7))]),
            ),
          ],
          child: const MaterialApp(home: MaintenanceScreen()),
        ),
      );
      await tester.pumpAndSettle();
    });
    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, OhColors.sage600);
  });
}
