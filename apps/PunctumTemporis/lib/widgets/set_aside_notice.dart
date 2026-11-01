import 'package:flutter/material.dart';

/// One plain strip above the screen after the app set metadata.json aside:
/// what happened, the kept file's name, and that nothing was deleted
/// (StorageService.setAsideNotice). The family dismisses it; it is
/// never shown again for the same set-aside.
class SetAsideNotice extends StatelessWidget {
  const SetAsideNotice(
      {super.key, required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.info_outline,
                    size: 20, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ),
      ),
    );
  }
}

/// A `MaterialApp.builder` step: [message] above [screen], or the screen
/// alone when there is nothing to tell.
Widget withSetAsideNotice(BuildContext context, Widget screen,
    {required String? message, required VoidCallback onDismiss}) {
  if (message == null) return screen;
  return Column(
    children: [
      SetAsideNotice(message: message, onDismiss: onDismiss),
      Expanded(
        child: MediaQuery.removePadding(
            context: context, removeTop: true, child: screen),
      ),
    ],
  );
}
