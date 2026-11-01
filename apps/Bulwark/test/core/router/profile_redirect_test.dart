import 'package:bulwark/core/router/app_router.dart';
import 'package:bulwark/features/adoption/data/profile_repository.dart';
import 'package:bulwark/features/adoption/domain/enums.dart';
import 'package:bulwark/features/adoption/domain/profile.dart';
import 'package:bulwark/features/adoption/presentation/providers.dart';
import 'package:bulwark/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/adoption_harness.dart';

Profile _profile({required bool onboarded}) => Profile(
      wakeMinutes: 7 * 60,
      bedMinutes: 22 * 60,
      goal: Goal.general,
      pace: Pace.moderate,
      onboarded: onboarded,
    );

/// The router re-runs its redirect when the profile changes, through its own
/// `ref.listen(profileProvider)`. On riverpod 3 a provider's own listens stop
/// once nothing listens to that provider, so this pins that the app's way of
/// holding the router (watched above the navigator, as `BulwarkApp` does)
/// keeps the redirect live: a profile write plus an invalidate moves the
/// household with no navigation call of its own.
void main() {
  testWidgets('a profile change re-runs the redirect, both ways',
      (tester) async {
    final db = memoryDatabase();
    late ProviderContainer container;

    // Drift answers on the real event loop; give it real time, then let the
    // fake clock run the fade transitions.
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [...adoptionOverrides(db: db), ...backupOverrides()],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        );
      }),
    ));
    await settle();

    String where() => container
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;

    expect(where(), '/onboarding');

    await tester.runAsync(
        () => ProfileRepository(db).save(_profile(onboarded: true)));
    container.invalidate(profileProvider);
    await settle();
    expect(where(), '/');

    await tester.runAsync(
        () => ProfileRepository(db).save(_profile(onboarded: false)));
    container.invalidate(profileProvider);
    await settle();
    expect(where(), '/onboarding');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  // Riverpod 3 changed `AsyncValue.value` on a failure from a rethrow to
  // null. The redirect reads `value` only behind `hasValue`, so a failed
  // profile read holds still: it never reads as "not onboarded" and never
  // sends a household with a profile back to onboarding.
  testWidgets('a failed profile read does not send the household to '
      'onboarding', (tester) async {
    final db = memoryDatabase();
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...adoptionOverrides(db: db),
        ...backupOverrides(),
        profileProvider
            .overrideWith((ref) async => throw Exception('disk read failed')),
      ],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        );
      }),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        '/');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
