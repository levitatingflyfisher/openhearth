// On the web porch's state lives in the browser, and clearing the browser's
// website data erases it. The family opens the app in a phone browser, so
// the real PorchApp shows the fleet's data notice above every screen on the
// web (beside porch's own red Web preview banner about keys), and nothing
// off the web.
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {
  tearDown(() => debugOhWebDataNoticeOnWeb = null);

  testWidgets('on the web the app shows the data notice once',
      (tester) async {
    debugOhWebDataNoticeOnWeb = true;
    await pumpPorch(tester, await UiWorld.onboarded());
    expect(find.text(ohWebDataNotice), findsOneWidget);
  });

  testWidgets('off the web the app shows no data notice', (tester) async {
    debugOhWebDataNoticeOnWeb = false;
    await pumpPorch(tester, await UiWorld.onboarded());
    expect(find.text(ohWebDataNotice), findsNothing);
  });
}
