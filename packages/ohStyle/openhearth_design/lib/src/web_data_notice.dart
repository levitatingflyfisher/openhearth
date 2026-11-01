import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// The one line every fleet app shows on the web, where its data lives in
/// the browser: clearing the browser's website data erases it. Checked by a
/// blind reader (14 Nov 2026), kept here once so every app says it the same
/// way.
/// Tests only: when set, the notice acts as on the web (true) or off it
/// (false) wherever `onWeb` is not passed, so an app's own test can pump its
/// real MaterialApp and see the strip. Reset it to null in tearDown.
bool? debugOhWebDataNoticeOnWeb;

const ohWebDataNotice = 'Your data stays on this device, in this browser. '
    'If you clear the browser’s website data, it is erased.';

/// [ohWebDataNotice] as one quiet strip: an info icon and the line in
/// `bodySmall`, on the theme's container colour. Draws nothing off the web,
/// so an app can place it at the top of its main screen unconditionally.
/// Nothing to dismiss and nothing stored: it is one plain fact, always true
/// on the web.
class OhWebDataNotice extends StatelessWidget {
  /// Null follows the platform ([kIsWeb]), or [debugOhWebDataNoticeOnWeb]
  /// when a test sets it; tests may also pass true or false here.
  final bool? onWeb;
  const OhWebDataNotice({super.key, this.onWeb});

  @override
  Widget build(BuildContext context) {
    if (!(onWeb ?? debugOhWebDataNoticeOnWeb ?? kIsWeb)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.info_outline,
                  size: 16, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ohWebDataNotice,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A `MaterialApp.builder` that shows [OhWebDataNotice] above every screen
/// on the web, with the screen filling the rest. Off the web it returns the
/// screen untouched. An app with its own builder calls this on its result.
Widget ohWebDataNoticeBuilder(BuildContext context, Widget? child,
    {bool? onWeb}) {
  final screen = child ?? const SizedBox.shrink();
  if (!(onWeb ?? debugOhWebDataNoticeOnWeb ?? kIsWeb)) return screen;
  return Column(
    children: [
      SafeArea(bottom: false, child: OhWebDataNotice(onWeb: onWeb)),
      Expanded(
        child: MediaQuery.removePadding(
            context: context, removeTop: true, child: screen),
      ),
    ],
  );
}
