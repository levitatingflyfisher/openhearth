import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:mantle/features/ranking/presentation/members_screen.dart';

// A failed read of the removed members says so, with Try again. It is never
// drawn as nobody removed: Recently removed is the only way to bring a
// person back. After Try again, with a read that works, they are there.

class _Members extends MembersDao {
  _Members(super.db);
  bool failing = true;
  @override
  Future<List<MemberRow>> removed() async {
    if (failing) throw Exception('disk read failed');
    return super.removed();
  }
}

void main() {
  late MantleDatabase db;

  setUp(() {
    db = MantleDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failed read of removed members is said, never empty',
      (tester) async {
    final dao = _Members(db);
    await dao.add(
        id: 'a', label: 'Ada', color: 0xFF000000, createdAt: DateTime(2026));
    await dao.add(
        id: 'b', label: 'Ben', color: 0xFF000000, createdAt: DateTime(2026));
    await dao.remove('b');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        membersDaoProvider.overrideWithValue(dao),
        themePreferenceProvider
            .overrideWith((ref) async => ThemePreference.light),
      ],
      child: const MaterialApp(home: MembersScreen()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Couldn’t read who was removed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    dao.failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsNothing);
    expect(find.text('Ben'), findsOneWidget);
  });
}
