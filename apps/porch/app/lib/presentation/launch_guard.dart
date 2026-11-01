// LaunchGuard — runs porch's whole start-up under a screen.
//
// Start-up (libsodium, the documents folder, the theme read) used to run
// before runApp, so a failure there left a blank screen with no way to try
// again. Now runApp shows this guard first: a spinner while start-up runs,
// the fleet's error view with Try again if it fails, and the app it built
// once it succeeds. Try again runs the whole start-up again; nothing
// retries on its own.
import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'app.dart' show porchAmberDark, porchAmberLight;

class LaunchGuard extends StatefulWidget {
  /// Builds the app: the production one is bootstrap().
  final Future<Widget> Function() start;
  const LaunchGuard({super.key, required this.start});

  @override
  State<LaunchGuard> createState() => _LaunchGuardState();
}

class _LaunchGuardState extends State<LaunchGuard> {
  late Future<Widget> _started = widget.start();

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
        future: _started,
        builder: (context, snap) {
          final app = snap.data;
          if (app != null) return app;
          // Before the app exists there is no theme choice yet: follow the
          // phone, in porch's own colours.
          return MaterialApp(
            title: 'Porch',
            debugShowCheckedModeBanner: false,
            theme: OhTheme.light(appAccent: porchAmberLight),
            darkTheme: OhTheme.hearthDark(appAccent: porchAmberDark),
            home: Scaffold(
              body: SafeArea(
                child: Center(
                  child: snap.hasError
                      ? OhErrorState.fromError(
                          snap.error!,
                          stackTrace: snap.stackTrace,
                          icon: Icons.error_outline,
                          onRetry: () {
                            final again = widget.start();
                            setState(() {
                              _started = again;
                            });
                          },
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ),
          );
        },
      );
}
