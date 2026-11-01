import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';
import 'package:peckish/features/sync/presentation/sync_screen.dart';
import 'package:peckish/shared/widgets/undo_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/erase_overrides.dart';

// "Erase all data" says "Deletes everything on this device", and a restore
// replaces the household's data. After either, nothing from before may stay
// on screen, and nothing from before may be written back. Every secret in
// these tests is made up.
final _refProvider = Provider<Ref>((ref) => ref);

const _madeUpKey = 'made-up-test-key-not-real';
const _madeUpPhrase = 'made up stove phrase';
const _madeUpCode = 'made-up-household-code';

Future<EraseHarness> _harness() async {
  SharedPreferences.setMockInitialValues({
    'ai_backend': 'anthropic',
    'ai_base_url': 'http://example.invalid',
    'ai_model': 'made-up-model',
    'ai_stove_host': 'stove.invalid',
    'ai_stove_port': 9,
  });
  final h = EraseHarness(AppDatabase(NativeDatabase.memory()),
      await SharedPreferences.getInstance());
  h.keys.value = _madeUpKey;
  await h.stove.write(_madeUpPhrase);
  await h.sync.write(_madeUpCode);
  await h.drafts.write('edit:r1', const RecipeDraft(title: 'Old soup'));
  return h;
}

/// Mounts a ref for [eraseAllData], which takes a WidgetRef.
Future<(WidgetRef, ProviderContainer)> _mount(
    WidgetTester tester, EraseHarness h) async {
  late WidgetRef captured;
  await tester.pumpWidget(ProviderScope(
    overrides: h.overrides,
    child: Consumer(builder: (context, ref, _) {
      captured = ref;
      return const SizedBox();
    }),
  ));
  final container =
      ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
  return (captured, container);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// How many times an offered Undo's onCommit ran. An erase or a restore
/// must never run one: it was written against the data from before.
var _commits = 0;

/// A delete that happened just before: its Undo would write the row back.
/// It carries an onCommit, which the reset must leave unrun.
void _offerUndo(ProviderContainer c) {
  _commits = 0;
  c.read(undoControllerProvider).show(
        message: 'Deleted Soup',
        onUndo: () async {},
        onCommit: () async => _commits++,
      );
}

void main() {
  group('Erase all data', () {
    testWidgets('drops a pending Undo, so it cannot bring data back',
        (tester) async {
      final h = await _harness();
      final (ref, c) = await _mount(tester, h);
      _offerUndo(c);
      expect(c.read(undoControllerProvider).pending, isNotNull);

      await tester.runAsync(() => eraseAllData(ref));

      expect(c.read(undoControllerProvider).pending, isNull,
          reason: 'tapping Undo would write the erased row back');
      expect(_commits, 0, reason: 'an erase never commits the old offer');
      await _unmount(tester);
      await h.db.close();
    });

    testWidgets('deletes the AI key, the stove phrase and the AI settings',
        (tester) async {
      final h = await _harness();
      final (ref, _) = await _mount(tester, h);

      await tester.runAsync(() => eraseAllData(ref));

      expect(h.keys.value, isNull, reason: 'the AI key is still stored');
      expect(await tester.runAsync(h.stove.read), isNull,
          reason: 'the stove phrase is still stored');
      expect(h.prefs.getKeys().where((k) => k.startsWith('ai_')), isEmpty,
          reason: 'an AI setting is still stored');
      await _unmount(tester);
      await h.db.close();
    });

    testWidgets('the AI settings on screen go back to off at once',
        (tester) async {
      final h = await _harness();
      final (ref, c) = await _mount(tester, h);
      final before =
          await tester.runAsync(() => c.read(aiConfigProvider.future));
      expect(before!.backend, AiBackend.anthropic);

      await tester.runAsync(() => eraseAllData(ref));

      final after =
          await tester.runAsync(() => c.read(aiConfigProvider.future));
      expect(after!.backend, AiBackend.none);
      expect(after.anthropicKey, isNull);
      await _unmount(tester);
      await h.db.close();
    });

    testWidgets('deletes the household sync code and stops serving',
        (tester) async {
      final h = await _harness();
      h.server.isRunning = true;
      final (ref, c) = await _mount(tester, h);
      c.read(lanSyncServerProvider);

      await tester.runAsync(() => eraseAllData(ref));

      expect(await tester.runAsync(h.sync.read), isNull,
          reason: 'the household sync code is still stored');
      expect(h.server.isRunning, isFalse,
          reason: 'a peer could still sync into the erased data');
      await _unmount(tester);
      await h.db.close();
    });

    testWidgets('resets the suggestion card and keeps the theme',
        (tester) async {
      final h = await _harness();
      final (ref, c) = await _mount(tester, h);
      final settings = c.read(settingsRepositoryProvider);
      await tester.runAsync(() async {
        await settings.setThemeMode(OhThemeModePreference.dark);
        await settings.setSuggestionsEnabled(false);
        await settings.setSuggestionsDismissedDay('2026-11-01');
      });

      await tester.runAsync(() => eraseAllData(ref));

      final prefs = (await tester.runAsync(settings.getUserPrefs))!;
      expect(prefs.themeMode, OhThemeModePreference.dark,
          reason: 'the dialog promises the theme is kept');
      expect(prefs.suggestionsEnabled, isTrue);
      expect(prefs.suggestionsDismissedDay, isNull);
      await _unmount(tester);
      await h.db.close();
    });
  });

  group('After a restore', () {
    late EraseHarness h;
    late ProviderContainer c;
    setUp(() async {
      h = await _harness();
      c = ProviderContainer(overrides: h.overrides);
    });
    tearDown(() async {
      c.dispose();
      await h.db.close();
    });

    test('a pending Undo is dropped, so it cannot write over the restore',
        () async {
      _offerUndo(c);
      await afterBackupRestore(c.read(_refProvider));
      expect(c.read(undoControllerProvider).pending, isNull,
          reason: 'tapping Undo would write an old row into the restored data');
      expect(_commits, 0, reason: 'a restore never commits the old offer');
    });

    test(
        'unsaved recipe drafts are cleared, so an old edit cannot be saved '
        'over a restored recipe', () async {
      await afterBackupRestore(c.read(_refProvider));
      expect(h.drafts.read('edit:r1'), isNull);
    });

    test(
        'the AI settings, the stove phrase and the sync code are kept: the '
        'backup does not carry them, and a restore is not an erase', () async {
      await afterBackupRestore(c.read(_refProvider));
      expect(h.keys.value, _madeUpKey);
      expect(await h.stove.read(), _madeUpPhrase);
      expect(await h.sync.read(), _madeUpCode);
      expect(h.prefs.getString('ai_backend'), 'anthropic');
    });
  });
}
