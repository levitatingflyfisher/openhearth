import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/features/dashboard/presentation/widgets/items_by_month_chart.dart';
import 'package:still_life/features/dashboard/presentation/widgets/recent_activity_widget.dart';
import 'package:still_life/services/database/database.dart';

import '../../../../support/restore_harness.dart';
import '../../../../test_setup.dart';

/// The Dashboard tab stays alive under Settings, so its cards are on
/// screen, cached, while a restore runs. Each card must show the merged
/// data afterwards, and an ordinary edit too, without a restart.
void main() {
  ensureSqlite3();

  late AppDatabase db;
  late ProviderContainer container;

  Future<void> pumpCards(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [RecentActivityWidget(), ItemsByMonthChart()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    db = AppDatabase.memory();
    container = ProviderContainer(overrides: restoreOverrides(db));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets('Recent Activity shows the restored item', (tester) async {
    await tester.runAsync(() => seedHousehold(db));
    await pumpCards(tester);
    expect(find.text('Old lamp'), findsOneWidget);

    // Real time, not the test's fake clock: the restore waits on the
    // database's change notices.
    await tester.runAsync(
      () async => restoreBackup(
        container,
        await backupOf((src) => seedHousehold(src, itemName: 'Brass lamp')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Brass lamp'), findsOneWidget);
    expect(find.text('Old lamp'), findsNothing);
  });

  testWidgets('Items Added by Month counts the restored items', (tester) async {
    // Everything on this device is years old, so the chart has nothing to
    // show; the backup brings an item added this month.
    await tester.runAsync(() => seedHousehold(db, createdAt: DateTime(2020)));
    await pumpCards(tester);
    expect(find.text('Items Added by Month'), findsNothing);

    await tester.runAsync(
      () async =>
          restoreBackup(container, await backupOf((src) => seedHousehold(src))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Items Added by Month'), findsOneWidget);
  });

  testWidgets('Recent Activity follows an ordinary edit', (tester) async {
    await tester.runAsync(() => seedHousehold(db));
    await pumpCards(tester);
    expect(find.text('Old lamp'), findsOneWidget);

    await tester.runAsync(() async {
      await (db.update(db.items)..where((t) => t.id.equals('item_1'))).write(
        ItemsCompanion(
          name: const Value('Desk lamp'),
          modifiedAt: Value(DateTime.now()),
        ),
      );
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();

    expect(find.text('Desk lamp'), findsOneWidget);
  });
}
