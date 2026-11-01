import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/features/insurance/presentation/screens/what_should_i_insure_screen.dart';
import 'package:still_life/services/database/database.dart' as db_pkg;

import '../../../../test_setup.dart';

Future<db_pkg.AppDatabase> setupDb({
  List<(String id, int value, bool insured)> items = const [],
}) async {
  final db = db_pkg.AppDatabase.memory();
  final now = DateTime(2025, 1, 1);
  await db
      .into(db.properties)
      .insert(
        db_pkg.PropertiesCompanion.insert(
          id: 'p',
          name: 'Home',
          createdAt: now,
          modifiedAt: now,
        ),
      );
  await db
      .into(db.rooms)
      .insert(
        db_pkg.RoomsCompanion.insert(
          id: 'r',
          propertyId: 'p',
          name: 'Living',
          createdAt: now,
          modifiedAt: now,
        ),
      );
  await db
      .into(db.categories)
      .insert(
        db_pkg.CategoriesCompanion.insert(
          id: 'c',
          name: 'Cat',
          createdAt: now,
          modifiedAt: now,
        ),
      );
  for (final (id, value, insured) in items) {
    await db
        .into(db.items)
        .insert(
          db_pkg.ItemsCompanion.insert(
            id: id,
            name: 'Item $id',
            categoryId: 'c',
            roomId: 'r',
            currentValueCents: Value(value),
            isInsured: Value(insured),
            createdAt: now,
            modifiedAt: now,
          ),
        );
  }
  return db;
}

GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const WhatShouldIInsureScreen()),
  ],
);

void main() {
  ensureSqlite3();

  testWidgets('lists uncovered items newest-value first and formats cents as dollars',
      (tester) async {
    final db = await setupDb(
      items: [('a', 10000, false), ('b', 150000, false), ('c', 20050, false)],
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Item b'), findsOneWidget);
    expect(find.text('Item a'), findsOneWidget);
    expect(find.text('Item c'), findsOneWidget);
    expect(find.text(r'$1,500.00'), findsOneWidget);
    expect(find.text(r'$150,000.00'), findsNothing);
    expect(find.text(r'$200.50'), findsOneWidget);
    expect(find.text(r'$100.00'), findsOneWidget);
  });

  testWidgets('shows empty state when nothing is uncovered', (tester) async {
    final db = await setupDb(items: [('a', 100, true)]);
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('marked as insured'), findsOneWidget);
  });
}
