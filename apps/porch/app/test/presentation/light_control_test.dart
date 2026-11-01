// The porch light control carries its state (audit humane-interface-07;
// both sides of the contested verbs-versus-adjectives row agree on this
// floor): one control, in one place, one size, showing whether the light
// is on or off, in both states. Before, Off was a full-width "I’m
// available" button and On a card with a small "Turn off" elsewhere.
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/home/home_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {
  testWidgets('the control keeps its place and size across off → on → off, '
      'and always shows which state the light is in', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);

    final control = find.byKey(porchLightKey);
    expect(control, findsOneWidget);
    final offRect = tester.getRect(control);
    expect(lightShowsOn(tester), isFalse);

    await tapItem(tester, lightSegment('On'));
    await tapItem(tester, find.text('Turn on the porch light'));

    expect(control, findsOneWidget);
    expect(tester.getRect(control), offRect,
        reason: 'the control moved or resized when the light came on');
    expect(lightShowsOn(tester), isTrue);

    await tapItem(tester, lightSegment('Off'));
    expect(tester.getRect(control), offRect);
    expect(lightShowsOn(tester), isFalse);
  });

  // A radio group: the checked segment is the state.
  testWidgets('screen readers hear the state on the control itself',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    final handle = tester.ensureSemantics();

    expect(tester.getSemantics(lightSegment('Off')),
        containsSemantics(
            label: 'Off', isChecked: true, isInMutuallyExclusiveGroup: true));
    expect(tester.getSemantics(lightSegment('On')),
        containsSemantics(
            label: 'On', isChecked: false, isInMutuallyExclusiveGroup: true));
    handle.dispose();
  });

  testWidgets('with no group the control is shown, off and disabled',
      (tester) async {
    final u = await UiWorld.onboarded();
    final env = await u.env();
    final state = (await u.store.load())!;
    state.groups.clear();
    await env.stateStore.save(state);
    await pumpPorch(tester, u);

    expect(find.byKey(porchLightKey), findsOneWidget);
    expect(lightShowsOn(tester), isFalse);
    expect(lightEnabled(tester), isFalse);
  });

  testWidgets('dismissing the sheet leaves the light off', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await tapItem(tester, lightSegment('On'));
    await tester.tapAt(const Offset(10, 10)); // the scrim
    await tester.pumpAndSettle();
    expect(lightShowsOn(tester), isFalse);
  });

}
