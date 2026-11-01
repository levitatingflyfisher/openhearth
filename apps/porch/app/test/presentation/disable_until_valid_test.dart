// Disable until valid: a control that would do nothing is shown as unable
// to act, with the missing piece named in place — never a live-looking
// button that returns in silence (audit: dont-make-me-think-02).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

bool enabled(WidgetTester tester, String label) {
  final f = find.ancestor(
      of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  return tester.widget<ButtonStyleButton>(f.first).onPressed != null;
}

void main() {
  // The backup used to wait for a person-picked PIN of 4 digits. Porch now
  // picks the 6 backup words itself, so there is nothing to wait for and no
  // PIN field anywhere.
  testWidgets('settings backup: no PIN to pick, Create backup is ready',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);
    await tapItem(tester, find.text('Save encrypted backup'));

    expect(find.textContaining('PIN'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        findsNothing);
    expect(enabled(tester, 'Create backup'), isTrue);
  });

  testWidgets('onboarding backup: no PIN to pick, Create encrypted backup '
      'is ready', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
    await tapItem(tester, find.text('I wrote them down'));

    expect(find.textContaining('PIN'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(enabled(tester, 'Create encrypted backup'), isTrue);
  });

  testWidgets('available sheet: with Custom chosen, the confirm button waits '
      'for a positive number of minutes', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await tapItem(tester, lightSegment('On'));
    const confirm = 'Turn on the porch light';
    expect(enabled(tester, confirm), isTrue);

    await tapItem(tester, find.text('Custom'));
    expect(enabled(tester, confirm), isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '0');
    await tester.pump();
    expect(enabled(tester, confirm), isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '45');
    await tester.pump();
    expect(enabled(tester, confirm), isTrue);
  });

  testWidgets('new group: Create stays disabled while the name is blank',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await tapItem(tester, barAction('Groups'));
    await tapItem(tester, find.byType(FloatingActionButton));

    expect(enabled(tester, 'Create'), isFalse);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(enabled(tester, 'Create'), isFalse);
    await tester.enterText(find.byType(TextField), 'Book club');
    await tester.pump();
    expect(enabled(tester, 'Create'), isTrue);
  });

  testWidgets('home with no groups: the porch light control is disabled and '
      'the screen says how to get a group', (tester) async {
    final u = await UiWorld.onboarded();
    final state = (await u.store.load())!;
    state.groups.clear();
    await u.store.save(state);
    await pumpPorch(tester, u);

    expect(lightEnabled(tester), isFalse);
    expect(find.textContaining('not in any group'), findsOneWidget);
    await tapItem(tester, find.text('Open Groups'));
    expect(find.text('Join with a code'), findsOneWidget);
  });
}
