// Boot smoke test: a fresh install renders onboarding (age gate first,
// before any key exists and before any network could be touched).
import 'package:flutter_test/flutter_test.dart';

import 'presentation/support/pump.dart';
import 'presentation/support/ui_world.dart';

void main() {
  testWidgets('fresh install boots to the age gate', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    expect(find.textContaining('13 or older'), findsOneWidget);
    expect(await u.keys.readEntropy(), isNull);
    expect(u.world.relay.callLog, isEmpty);
  });
}
