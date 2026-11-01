import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/services/database/database.dart';

import '../../../../test_setup.dart';

// The clocks go back on 1 November 2026 (United States), so the day of the
// change is 25 hours long. Adding 72 hours to the evening of 30 October lands
// at 23:00 on 1 November, which left a warranty ending at midnight on
// 2 November out of a "within 3 days" list. Under TZ=UTC this passes before
// the fix; under TZ=America/New_York it does not.
void main() {
  ensureSqlite3();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    final t = DateTime(2025, 1, 1);
    await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat1', name: 'Electronics', createdAt: t, modifiedAt: t));
    await db.into(db.properties).insert(PropertiesCompanion.insert(
        id: 'prop1', name: 'Home', createdAt: t, modifiedAt: t));
    await db.into(db.rooms).insert(RoomsCompanion.insert(
        id: 'room1', propertyId: 'prop1', name: 'Room', createdAt: t, modifiedAt: t));
  });

  tearDown(() => db.close());

  Future<void> addItem(String id, DateTime warranty) {
    final t = DateTime(2025, 1, 1);
    return db.into(db.items).insert(ItemsCompanion.insert(
          id: id,
          name: id,
          categoryId: 'cat1',
          roomId: 'room1',
          warrantyExpiration: Value(warranty),
          createdAt: t,
          modifiedAt: t,
        ));
  }

  test('a warranty ending three calendar days out is within 3 days', () async {
    await addItem('edge', DateTime(2026, 11, 2));
    await addItem('past', DateTime(2026, 11, 3));
    final found = await withClock(
      Clock.fixed(DateTime(2026, 10, 30)),
      () => db.itemDao.getWarrantyExpiringSoon(withinDays: 3),
    );
    expect(found.map((i) => i.id), ['edge']);
  });
}
