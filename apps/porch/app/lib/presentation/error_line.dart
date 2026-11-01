// An inline error under a form: colour, icon and word together (fleet
// colour language: an error is never red text alone).
import 'package:flutter/material.dart';

class ErrorLine extends StatelessWidget {
  final String message;

  const ErrorLine(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 8),
          child: Icon(Icons.error_outline,
              key: const Key('error-line-icon'), size: 20, color: color),
        ),
        Expanded(child: Text(message, style: TextStyle(color: color))),
      ],
    );
  }
}
