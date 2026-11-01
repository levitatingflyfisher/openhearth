// web_preview — the honest "this is a preview" notice, web-only.
//
// Porch's security story is structural, not promised. On web the two device
// secrets fall back to browser storage (localStorage via
// flutter_secure_storage_web) and the encrypted state blob lives in
// localStorage too — weaker than the Android Keystore-backed app, and the
// browser can evict it. That downgrade must be visible, not buried, so this
// banner shows on every web build and the settings screen repeats the point.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// True only in the web preview build.
const bool isWebPreview = kIsWeb;

/// The one-line honesty message, reused by the banner and settings.
const String webPreviewMessage =
    'Web preview. Your keys are stored in this browser (localStorage), which '
    'is less secure than the Android app. Don’t use it with a real '
    'identity you care about.';

/// A persistent, undismissable notice. Renders nothing off web, so it is safe
/// to place unconditionally at the top of any screen.
class WebPreviewBanner extends StatelessWidget {
  const WebPreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isWebPreview) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            // Expanded so the message wraps instead of overflowing at large
            // textScale on a narrow (320 dp) screen (house a11y sweep).
            Expanded(
              child: Text(webPreviewMessage,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}
