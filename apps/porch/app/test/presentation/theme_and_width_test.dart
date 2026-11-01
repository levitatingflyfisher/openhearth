// Fleet rulings, checked on porch's own screens:
//  - theme: light, dark or follow the phone, default follow the phone, any
//    choice at most two taps from Home, and the choice persists;
//  - width: every screen's content is capped by OhPage, so a tablet or a
//    browser does not stretch the phone layout across 1024 px.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/data/theme_store.dart';
import 'package:porch_app/presentation/groups/group_detail_screen.dart';
import 'package:porch_app/presentation/groups/groups_screen.dart';
import 'package:porch_app/presentation/home/home_screen.dart';
import 'package:porch_app/presentation/join/join_screen.dart';
import 'package:porch_app/presentation/onboarding/onboarding_flow.dart';
import 'package:porch_app/presentation/settings/settings_screen.dart';
import 'package:porch_app/presentation/settings/what_leaves_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

ThemeMode _appThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  group('theme', () {
    testWidgets('defaults to following the phone', (tester) async {
      final u = await UiWorld.onboarded();
      await pumpPorch(tester, u);
      expect(_appThemeMode(tester), ThemeMode.system);
    });

    testWidgets('Dark is two taps from Home, and the choice is stored', (
      tester,
    ) async {
      final u = await UiWorld.onboarded();
      await pumpPorch(tester, u);

      await tapItem(tester, find.byTooltip('More'));
      await tapItem(tester, find.text('Dark'));

      expect(_appThemeMode(tester), ThemeMode.dark);
      expect(await u.prefs.read(ThemePreferenceStore.key), 'dark');
    });

    testWidgets('a stored choice is what the app opens with', (tester) async {
      final u = await UiWorld.onboarded();
      u.initialTheme = OhThemeModePreference.light;
      await pumpPorch(tester, u);
      expect(_appThemeMode(tester), ThemeMode.light);
    });

    testWidgets('Settings carries the fleet theme toggle too', (tester) async {
      final u = await UiWorld.onboarded();
      await pumpScreen(tester, u, const SettingsScreen());
      expect(find.byType(OhThemeToggle), findsOneWidget);
    });

    // The fleet's one publisher line, under About, as in the other apps.
    testWidgets('Settings names the publisher under About', (tester) async {
      final u = await UiWorld.onboarded();
      await pumpScreen(tester, u, const SettingsScreen());
      await tester.scrollUntilVisible(
        find.text(ohPublisherLine),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Published by Intergenerational Symbolic Systems'),
          findsOneWidget);
      expect(find.byType(OhPublisherLine), findsOneWidget);
    });

    // The publisher's rule: never ask for donations, so Settings has no
    // donate link or support plea (13 Nov).
    testWidgets('Settings asks for no donation', (tester) async {
      final u = await UiWorld.onboarded();
      await pumpScreen(tester, u, const SettingsScreen());
      await tester.scrollUntilVisible(
        find.text(ohPublisherLine),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('donate'), findsNothing);
      expect(find.textContaining('support it'), findsNothing);
      expect(find.textContaining('porch.example'), findsNothing);
    });
  });

  group('every screen is width-capped at 1024 dp', () {
    Future<void> atTablet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> expectCapped(
      WidgetTester tester,
      UiWorld u,
      Widget screen,
    ) async {
      await atTablet(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: u.overrides,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(OhPage),
        findsWidgets,
        reason: '${screen.runtimeType} has no OhPage',
      );
      final page = tester.getRect(find.byType(OhPage).first);
      final content = tester.getRect(
        find
            .descendant(
              of: find.byType(OhPage).first,
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(page.width, 1024);
      expect(
        content.width,
        lessThanOrEqualTo(OhPage.phoneMaxWidth),
        reason: '${screen.runtimeType} content is ${content.width} wide',
      );
    }

    testWidgets('Onboarding', (tester) async {
      final u = await UiWorld.fresh();
      await expectCapped(tester, u, const OnboardingFlow(hasIdentity: false));
    });

    testWidgets('Home', (tester) async {
      final u = await UiWorld.onboarded();
      await expectCapped(tester, u, const HomeScreen());
    });

    testWidgets('Groups', (tester) async {
      final u = await UiWorld.onboarded();
      await expectCapped(tester, u, const GroupsScreen());
    });

    testWidgets('Group detail', (tester) async {
      final u = await UiWorld.onboarded();
      final uuid = (await u.store.load())!.groups.single.groupUuid;
      await expectCapped(tester, u, GroupDetailScreen(groupUuid: uuid));
    });

    testWidgets('Join', (tester) async {
      final u = await UiWorld.onboarded();
      await expectCapped(tester, u, const JoinScreen());
    });

    testWidgets('Settings', (tester) async {
      final u = await UiWorld.onboarded();
      await expectCapped(tester, u, const SettingsScreen());
    });

    testWidgets('What leaves your device', (tester) async {
      final u = await UiWorld.onboarded();
      await expectCapped(tester, u, const WhatLeavesScreen());
    });
  });
}
