// Relay truth on Home (audit: dont-make-me-think-01). The shipped default
// relay is a placeholder that can never resolve; until the person sets a
// real one, Home must say so plainly and must not word a local light as if
// friends could see it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/relay_config.dart';
import 'package:porch_app/presentation/settings/settings_screen.dart'
    show httpsOnlyRelayNote;

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {
  testWidgets('no relay configured: Home says so, and says what it means',
      (tester) async {
    final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
    await pumpPorch(tester, u);

    expect(find.text('No relay set up'), findsOneWidget);
    expect(find.textContaining('only on this phone'), findsWidgets);
    // The empty feed does not claim friends will show up.
    expect(find.textContaining("Nobody’s on the porch"), findsNothing);
    expect(find.textContaining('they show up here'), findsNothing);
    expect(find.textContaining("Friends can’t show up here yet"),
        findsOneWidget);
  });

  testWidgets('no relay configured: a light turned on is worded as local, '
      'not as seen', (tester) async {
    final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
    await pumpPorch(tester, u);

    await tapItem(tester, lightSegment('On'));
    await tapItem(tester, find.text('Turn on the porch light'));

    expect(find.text("You’re on the porch"), findsNothing);
    expect(find.text('Your light is on, on this phone only'), findsOneWidget);
    expect(lightShowsOn(tester), isTrue);
  });

  testWidgets('saving a relay URL in Settings clears the notice on return',
      (tester) async {
    final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
    await pumpPorch(tester, u);

    await tapItem(tester, find.text('Set up a relay'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Relay URL'), 'https://relay.example');
    await tapItem(tester, find.text('Save relay URL'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('No relay set up'), findsNothing);
    expect(find.textContaining("Nobody’s on the porch"), findsOneWidget);
  });

  testWidgets('a plain http relay address is refused in words, not saved',
      (tester) async {
    final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
    await pumpPorch(tester, u);

    await tapItem(tester, find.text('Set up a relay'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Relay URL'), 'http://relay.example');
    await tapItem(tester, find.text('Save relay URL'));

    expect(find.text(httpsOnlyRelayNote), findsOneWidget);
    expect(find.textContaining('Relay saved'), findsNothing);
    expect(find.text('In effect: none, this phone only'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No relay set up'), findsOneWidget);
  });

  testWidgets('relay configured: no notice, the usual wording',
      (tester) async {
    final u = await UiWorld.onboarded(); // harness default: a configured relay
    await pumpPorch(tester, u);

    expect(find.text('No relay set up'), findsNothing);
    await tapItem(tester, lightSegment('On'));
    await tapItem(tester, find.text('Turn on the porch light'));
    expect(find.text("You’re on the porch"), findsOneWidget);
  });

  testWidgets('settings no longer tells a person that blank means a working '
      'default when the default is no relay', (tester) async {
    final u = await UiWorld.onboarded()..relayUrl = defaultRelayUrl;
    await pumpPorch(tester, u);
    await openSettings(tester);

    expect(find.textContaining('built-in default'), findsNothing);
    expect(find.textContaining('Leave blank and Porch stays on this phone'),
        findsOneWidget);
    expect(find.textContaining('none, this phone only'), findsOneWidget);
  });
}
