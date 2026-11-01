import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/features/case/data/case_providers.dart';
import 'package:reckon/features/case/domain/entities/poll.dart';
import 'package:reckon/features/predictions/data/prediction_providers.dart';
import 'package:reckon/features/reveal/presentation/reveal_screen.dart';

/// The reveal reads the decision to draw the two option chips and to let
/// the person commit. If that read fails, the screen must not open as if
/// the decision had no options: "Set resolution date" would then commit
/// option A, which the person never saw or chose. Riverpod 2's
/// `AsyncValue.value` rethrew the failure, so the screen failed to build;
/// riverpod 3's gives null. This pins the failure reaching the screen.
void main() {
  testWidgets('a failed read of the decision fails the reveal, never offers '
      'to commit an option the person did not see', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        caseByIdProvider.overrideWith(
            (ref, id) async => throw Exception('disk read failed')),
        pollsForCaseProvider.overrideWith((ref, id) async => <Poll>[]),
        duelForecastsForCaseProvider.overrideWith((ref, id) async => []),
      ],
      child: const MaterialApp(home: RevealScreen(caseId: 'c1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isA<Exception>());
    expect(find.text('Set resolution date'), findsNothing);
  });
}
