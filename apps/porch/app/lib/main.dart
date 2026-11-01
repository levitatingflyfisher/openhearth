import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'move/move_page.dart';
import 'presentation/launch_guard.dart';

// Start-up runs under LaunchGuard, so a failure in it is shown with
// Try again instead of leaving a blank screen.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // returns here, before anything at the normal start can write.
  if (ohMovePage) {
    runApp(const LaunchGuard(start: bootstrapMovePage));
    return;
  }
  runApp(const LaunchGuard(start: bootstrap));
}
