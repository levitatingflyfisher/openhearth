import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'app/root_overrides.dart';
import 'app/theme.dart';
import 'core/providers/retry_policy.dart';
import 'features/move/move_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write. Reading
  // the preferences writes nothing.
  if (ohMovePage) {
    final prefs = await SharedPreferences.getInstance();
    runApp(MovePageApp(
      overrides: liltRootOverrides(prefs: prefs),
      theme: LiltTheme.light(),
      darkTheme: LiltTheme.dark(),
    ));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    liltProviderScope(
      overrides: liltRootOverrides(prefs: prefs),
      child: const LiltApp(),
    ),
  );
}
