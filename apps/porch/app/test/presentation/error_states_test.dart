// No raw exception reaches a person (fleet C10). Onboarding stores the
// error and shows it later, which C10 cannot see statically, so this file
// pins the site: a failing keystore on the very first tap must produce a
// sentence, with the exception text only behind Details. An Error
// (StateError, StateCorruptError) gets the same sentence as an Exception.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/state_store.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

/// A keystore that reads fine and refuses to store the identity, the way a
/// locked or broken platform keystore does. The state key, minted at
/// launch, still goes in, so the app reaches the age gate.
class _RefusingSecretStore extends InMemorySecretStore {
  final Object failure;
  _RefusingSecretStore(this.failure);

  @override
  Future<void> write(String key, String value) async {
    if (key == PorchKeyStore.entropyKey) throw failure;
    return super.write(key, value);
  }
}

/// A state store whose loads can be made to fail, and counts saves.
class _ArmedStateStore implements StateStore {
  final StateStore inner;
  Object? failLoads;
  int saves = 0;
  _ArmedStateStore(this.inner);

  @override
  Future<PorchState?> load() async {
    final failure = failLoads;
    if (failure != null) throw failure;
    return inner.load();
  }

  @override
  Future<void> save(PorchState state) {
    saves++;
    return inner.save(state);
  }

  @override
  Future<void> clear() => inner.clear();
}

void main() {
  testWidgets('a keygen failure on the first screen is a sentence, not '
      'the exception', (tester) async {
    final u = await UiWorld.fresh(
        secrets: _RefusingSecretStore(
            Exception('PlatformException(keystore-busy, KeyStore locked)')));
    await pumpPorch(tester, u);

    await tapItem(tester, find.text("I’m 13 or older"));

    expect(find.textContaining('keystore-busy'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.byType(OhErrorState), findsOneWidget);
    expect(find.text(OhErrorMessages.generic), findsOneWidget);

    // The raw text stays reachable for a bug report, behind Details.
    await tapItem(tester, find.text('Details'));
    expect(find.textContaining('keystore-busy'), findsOneWidget);
  });
  testWidgets('an Error on the first screen (StateError) is a sentence too',
      (tester) async {
    final u = await UiWorld.fresh(
        secrets: _RefusingSecretStore(StateError('keystore-locked')));
    await pumpPorch(tester, u);

    await tapItem(tester, find.text("I’m 13 or older"));

    expect(find.textContaining('keystore-locked'), findsNothing);
    expect(find.byType(OhErrorState), findsOneWidget);
    expect(find.text(OhErrorMessages.generic), findsOneWidget);
    await tapItem(tester, find.text('Details'));
    expect(find.textContaining('keystore-locked'), findsOneWidget);
  });

  testWidgets('a state file that stops opening mid-onboarding '
      '(StateCorruptError) is a sentence, and nothing is saved over it',
      (tester) async {
    final u = await UiWorld.fresh();
    final store = _ArmedStateStore(u.store);
    u.appStateStore = store;
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
    await tapItem(tester, find.text('I wrote them down'));
    await tapItem(tester, find.text('Skip for now'));
    await tester.enterText(find.byType(TextField), 'Alice');
    store
      ..saves = 0
      ..failLoads = StateCorruptError('decryption failed');

    await tapItem(tester, find.text('Finish setup'));

    expect(find.textContaining('decryption failed'), findsNothing);
    expect(find.byType(OhErrorState), findsOneWidget);
    expect(find.text(OhErrorMessages.generic), findsOneWidget);
    expect(store.saves, 0);
  });
}
