import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/features/case/data/case_providers.dart';
import 'package:reckon/features/case/domain/entities/case.dart';
import 'package:reckon/features/case/presentation/home_screen.dart';
import 'package:reckon/shared/theme/reckon_theme.dart';

Case _case(String id, String question) => Case(
      id: id,
      createdAt: DateTime.utc(2026, 11, 1),
      deadline: null,
      status: CaseStatus.open,
      question: question,
      optionA: 'Yes',
      optionB: 'No',
      statedCriteria: const [],
      stakes: Stakes.medium,
      regretHorizon: RegretHorizon.months,
      category: 'other',
    );

/// A decision written while another screen covers Home (intake, a case,
/// the group vote) must be on Home when the person comes back. Riverpod 3
/// pauses a covered screen's watches; this pins that Home catches up.
void main() {
  testWidgets('Home shows a decision added while it was covered',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final cases = StreamController<List<Case>>();
    addTearDown(cases.close);
    cases.add([_case('c1', 'Take the new job?')]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        openCasesStreamProvider.overrideWith((ref) => cases.stream),
      ],
      child: MaterialApp(theme: ReckonTheme.light(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Take the new job?'), findsOneWidget);

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covering')))));
    await tester.pumpAndSettle();

    // Proves the test runs the paused case: Home's tickers are off.
    final homeContext = tester.element(
        find.byType(HomeScreen, skipOffstage: false));
    expect(TickerMode.of(homeContext), isFalse);

    cases.add([
      _case('c1', 'Take the new job?'),
      _case('c2', 'Move the garden?'),
    ]);
    await tester.pumpAndSettle();

    nav.pop();
    await tester.pumpAndSettle();

    expect(find.text('Take the new job?'), findsOneWidget);
    expect(find.text('Move the garden?'), findsOneWidget);
  });
}
