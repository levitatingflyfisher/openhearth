import 'package:flutter/widgets.dart';
import 'package:mantle/app/app.dart';
import 'package:mantle/app/root_overrides.dart';
import 'package:mantle/features/move/move_page.dart';
import 'package:openhearth_design/openhearth_design.dart';

void main() {
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write.
  if (ohMovePage) {
    runApp(MovePageApp(
      overrides: mantleRootOverrides(),
      theme: OhTheme.light(),
      darkTheme: OhTheme.hearthDark(),
    ));
    return;
  }
  runApp(mantleProviderScope(child: const MantleApp()));
}
