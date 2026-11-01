// test/features/sessions/session_card_test.dart
//
// Item 4 of the 2026-04-09 multi-profile completion plan.
// Verifies SessionCard renders a profile attribution dot when a profile is
// provided, and the existing Everyone tag when it's a null-profile session in
// a filtered view. These two affordances are complementary, not redundant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sundial/core/storage/app_database.dart';
import 'package:sundial/features/profiles/presentation/profiles_screen.dart'
    show ProfileAvatar;
import 'package:sundial/features/sessions/presentation/session_card.dart';
import 'package:sundial/shared/theme/app_theme.dart';

Session _session({String? profileId, String id = 's1'}) => Session(
      id: id,
      startTime: DateTime(2026, 4, 9, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 4, 9, 10).millisecondsSinceEpoch,
      durationSecs: 3600,
      dateDay: '2026-04-09',
      profileId: profileId,
      createdAt: 0,
      updatedAt: 0,
    );

Profile _profile({
  String id = 'dad',
  String name = 'Dad',
  int colorValue = 0xFF00FF00,
  String? emoji,
}) =>
    Profile(
      id: id,
      name: name,
      emoji: emoji,
      colorValue: colorValue,
      sortOrder: 0,
      createdAt: 0,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SessionCard profile attribution', () {
    testWidgets(
        'shows ProfileAvatar dot when profile is provided',
        (tester) async {
      final s = _session(profileId: 'dad');
      final p = _profile();
      await tester.pumpWidget(_wrap(SessionCard(
        session: s,
        profile: p,
        onTap: () {},
        onDelete: () async => true,
      )));
      await tester.pump();

      expect(find.byType(ProfileAvatar), findsOneWidget,
          reason: 'a per-session dot must render when profile is passed');
    });

    testWidgets(
        'no dot when profile is null (Everyone session)',
        (tester) async {
      final s = _session(profileId: null);
      await tester.pumpWidget(_wrap(SessionCard(
        session: s,
        profile: null,
        onTap: () {},
        onDelete: () async => true,
      )));
      await tester.pump();

      expect(find.byType(ProfileAvatar), findsNothing);
    });

    testWidgets(
        'dot and Everyone tag are mutually exclusive per session',
        (tester) async {
      // A null-profile session in a filtered view: Everyone tag, no dot.
      final s = _session(profileId: null);
      await tester.pumpWidget(_wrap(SessionCard(
        session: s,
        profile: null,
        showEveryoneTag: true,
        onTap: () {},
        onDelete: () async => true,
      )));
      await tester.pump();

      expect(find.text('Everyone'), findsOneWidget);
      expect(find.byType(ProfileAvatar), findsNothing);
    });

    testWidgets(
        'emoji inside the dot renders when profile has one',
        (tester) async {
      final s = _session(profileId: 'dad');
      final p = _profile(emoji: '👨');
      await tester.pumpWidget(_wrap(SessionCard(
        session: s,
        profile: p,
        onTap: () {},
        onDelete: () async => true,
      )));
      await tester.pump();

      expect(find.text('👨'), findsOneWidget);
    });
  });

  group('SessionCard swipe delete (easy gesture confirms, per the ruling)', () {
    Future<void> swipe(WidgetTester tester) async {
      await tester.drag(find.byType(ListTile), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, naming the session and the act', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(_wrap(SessionCard(
        session: _session(),
        onTap: () {},
        onDelete: () async {
          deleted++;
          return true;
        },
      )));
      await swipe(tester);

      // The title names the object (duration + date), not "Delete session?".
      expect(find.text('Delete 1h on Thu, Apr 9?'), findsOneWidget);
      expect(find.text('Delete session'), findsOneWidget,
          reason: 'the button names the act, never OK or a bare Delete');
      // The swipe delete is permanent, and the dialog says so in words.
      expect(find.textContaining('for good'), findsOneWidget);
      expect(deleted, 0);
    });

    testWidgets('Cancel keeps the session', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(_wrap(SessionCard(
        session: _session(),
        onTap: () {},
        onDelete: () async {
          deleted++;
          return true;
        },
      )));
      await swipe(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, 0);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('confirming deletes', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(_wrap(SessionCard(
        session: _session(),
        onTap: () {},
        onDelete: () async {
          deleted++;
          return true;
        },
      )));
      await swipe(tester);
      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();

      expect(deleted, 1);
    });

    // A swipe used to remove the card before the delete was written, so a
    // failed delete left the card gone while the session stayed stored.
    testWidgets('a delete that fails keeps the card', (tester) async {
      await tester.pumpWidget(_wrap(SessionCard(
        session: _session(),
        onTap: () {},
        onDelete: () async => false,
      )));
      await swipe(tester);
      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsOneWidget);
    });
  });

  // At 320 wide and 3x text the title Row (duration plus the "Everyone"
  // tag) overflowed by 19 px with the app's real theme and cut the tag off.
  testWidgets('the Everyone tag row does not overflow at 320 wide, 3x text',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 800);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(3.0)),
        child: child!,
      ),
      home: Scaffold(
        body: SessionCard(
          session: _session(),
          showEveryoneTag: true,
          onTap: () {},
          onDelete: () async => true,
        ),
      ),
    ));
    await tester.pump();

    // A RenderFlex overflow is reported as an exception during layout.
    expect(tester.takeException(), isNull);
    final tag = tester.getRect(find.text('Everyone'));
    expect(tag.right, lessThanOrEqualTo(320),
        reason: 'the Everyone tag runs off the screen at $tag');
  });
}
