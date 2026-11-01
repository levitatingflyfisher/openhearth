// test/core/no_auto_retry_test.dart
//
// A failed read of the device's own data shows its error at once, with Try
// again, and is read once. Riverpod 3 retries a failing provider by default
// (up to 10 times, from 200 ms apart). For Mantle that would hold a blank
// spinner where the error and its Try again belong, and hammer a broken
// disk. These pins fail if a provider here starts to retry on its own.
//
// Each failure is an Exception (riverpod 3 never retries an Error), thrown
// by a dependency, so the provider's own policy is what is tested.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:mantle/features/content/data/content_repository.dart';
import 'package:mantle/features/content/domain/canon_item.dart';
import 'package:mantle/features/content/domain/spot_question.dart';
import 'package:mantle/features/content/domain/throughline.dart';
import 'package:mantle/features/ranking/presentation/members_screen.dart';
import 'package:mantle/features/solo/presentation/map_screen.dart';
import 'package:mantle/features/solo/presentation/solo_hub_screen.dart';
import 'package:mantle/features/tutor/content/data/menswear_repository.dart';
import 'package:mantle/features/tutor/content/domain/menswear_spot_question.dart';
import 'package:mantle/features/tutor/content/domain/menswear_term.dart';
import 'package:mantle/features/tutor/presentation/menswear_charter_start_screen.dart';
import 'package:mantle/features/tutor/presentation/tutor_hub_screen.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Counts every call by name and fails it, as a broken disk would.
mixin _Failing {
  final calls = <Symbol, int>{};

  int count(Symbol name) => calls[name] ?? 0;

  Never failRead(Symbol name) {
    calls[name] = count(name) + 1;
    throw Exception('disk read failed');
  }
}

class _FailingMembersDao with _Failing implements MembersDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      failRead(invocation.memberName);
}

class _FailingThroughlinesDao with _Failing
    implements DiscoveredThroughlinesDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      failRead(invocation.memberName);
}

class _FailingContent extends ContentRepository with _Failing {
  @override
  Future<List<CanonItem>> canon() async => failRead(#canon);
  @override
  Future<List<SpotQuestion>> spotQuestions() async => const [];
  @override
  Future<List<Throughline>> throughlines() async => const [];
}

class _FailingMenswear extends MenswearRepository with _Failing {
  @override
  Future<List<MenswearTerm>> terms() async => failRead(#terms);
  @override
  Future<List<MenswearSpotQuestion>> spotQuestions() async => const [];
}

class _NoContent extends ContentRepository {
  @override
  Future<List<CanonItem>> canon() async => const [];
  @override
  Future<List<SpotQuestion>> spotQuestions() async => const [];
  @override
  Future<List<Throughline>> throughlines() async => const [];
}

void main() {
  late MantleDatabase db;
  setUp(() => db = MantleDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget app(Widget home, List<Override> overrides) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          themePreferenceProvider
              .overrideWith((_) async => ThemePreference.light),
          ...overrides,
        ],
        child: MaterialApp(theme: OhTheme.light(), home: home),
      );

  /// Five seconds covers the first several retries of riverpod 3's default
  /// policy (200, 400, 800, 1600 ms apart).
  Future<void> waitFiveSeconds(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('Members: a failed list shows its error and is read once',
      (tester) async {
    final dao = _FailingMembersDao();
    await tester.pumpWidget(app(
        const MembersScreen(), [membersDaoProvider.overrideWithValue(dao)]));
    await waitFiveSeconds(tester);

    expect(find.text('The list of people didn’t load.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(dao.count(#all), 1);
    expect(dao.count(#removed), 1);
  });

  testWidgets('Wardrobe Charter start: a failed list is read once',
      (tester) async {
    final dao = _FailingMembersDao();
    await tester.pumpWidget(app(const MenswearCharterStartScreen(),
        [membersDaoProvider.overrideWithValue(dao)]));
    await waitFiveSeconds(tester);

    expect(find.text('The list of people didn’t load.'), findsOneWidget);
    expect(dao.count(#all), 1);
  });

  testWidgets('Explore: failed content shows its error and is read once',
      (tester) async {
    final content = _FailingContent();
    await tester.pumpWidget(app(const SoloHubScreen(),
        [contentRepositoryProvider.overrideWithValue(content)]));
    await waitFiveSeconds(tester);

    expect(find.text('The reading and practice content didn’t load.'),
        findsOneWidget);
    expect(content.count(#canon), 1);
  });

  testWidgets('Explore: a failed member list is read once', (tester) async {
    final dao = _FailingMembersDao();
    await tester.pumpWidget(app(const SoloHubScreen(), [
      membersDaoProvider.overrideWithValue(dao),
      contentRepositoryProvider.overrideWithValue(_NoContent()),
    ]));
    await waitFiveSeconds(tester);

    expect(dao.count(#all), 1);
  });

  testWidgets('Learn your style: a failed guide shows its error, read once',
      (tester) async {
    final menswear = _FailingMenswear();
    await tester.pumpWidget(app(const TutorHubScreen(),
        [menswearRepositoryProvider.overrideWithValue(menswear)]));
    await waitFiveSeconds(tester);

    expect(find.text('The menswear guide didn’t load.'), findsOneWidget);
    expect(menswear.count(#terms), 1);
  });

  testWidgets('Map: a failed read shows its error and is read once',
      (tester) async {
    final dao = _FailingThroughlinesDao();
    await tester.pumpWidget(app(const MapScreen(memberId: 'm1'), [
      discoveredThroughlinesDaoProvider.overrideWithValue(dao),
      contentRepositoryProvider.overrideWithValue(_NoContent()),
    ]));
    await waitFiveSeconds(tester);

    expect(find.text('Your map didn’t load.'), findsOneWidget);
    expect(dao.count(#forMember), 1);
  });
}
