// The web app moves to porch.familyflourishing.org (owner ruling, 15 Nov
// 2026). The move page build, at the old origin, reads the identity and the
// groups, and seals and shares the app's own backup file without saving it
// anywhere or changing a setting. The new site offers the way back on its
// first screen while the browser holds no identity.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:porch_app/data/backup_share.dart';
import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/move/move_page.dart';

import '../presentation/support/pump.dart';
import '../presentation/support/ui_world.dart';

PorchMoveReader _reader(UiWorld u) => PorchMoveReader(
      sodium: u.world.sodium,
      keys: u.keys,
      openStore: () async => u.store,
      limits: (
        ops: u.world.sodium.crypto.pwhash.opsLimitMin,
        mem: u.world.sodium.crypto.pwhash.memLimitMin,
      ),
    );

void main() {
  tearDown(debugResetOhMovedHereOffer);

  test('the addresses', () {
    expect(moveAppSlug, 'porch');
    expect(moveNewAddress, 'porch.familyflourishing.org');
  });

  test('the move page flag is off in a normal build', () {
    expect(ohMovePage, isFalse);
  });

  test('main opens the move page before anything else runs', () {
    final source = File('lib/main.dart').readAsStringSync();
    final body = source.substring(source.indexOf('void main()'));
    final moveAt = body.indexOf('if (ohMovePage)');
    expect(moveAt, isNonNegative);
    expect(
        body
            .substring(0, moveAt)
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .replaceAll(RegExp(r'\s+'), ''),
        'voidmain(){WidgetsFlutterBinding.ensureInitialized();');
  });

  test('an empty browser holds no records, and has nothing to seal',
      () async {
    final u = await UiWorld.fresh();
    final reader = _reader(u);
    expect(await reader.countRecords(), 0);
    expect(await reader.seal(), isNull);
  });

  test('the identity and each group are records; the sealed file opens with '
      'the 6 backup words, and nothing was written', () async {
    final secrets = _CountingSecrets();
    final u =
        await UiWorld.onboarded(name: 'Alice', seed: 9, secrets: secrets);
    final reader = _reader(u);
    final changesBefore = secrets.changes;
    final stateBefore = (await u.store.load())!.toJson().toString();

    expect(await reader.countRecords(), 2);
    final blob = (await reader.seal())!;

    final entropy = (await u.keys.readEntropy())!;
    final opened = openBackup(u.world.sodium,
        blob: blob,
        passphrase: backupPassphrase(u.world.sodium, entropy).join(' '));
    expect(opened.entropy, entropy);
    expect(secrets.changes, changesBefore);
    expect((await u.store.load())!.toJson().toString(), stateBefore);
    expect(u.backupSink.saved, isEmpty);
  });

  testWidgets('the move page build opens straight to the move screen, '
      'counts, and shares the sealed file', (tester) async {
    final u = await UiWorld.onboarded(name: 'Alice', seed: 9);
    final share = RecordingBackupShare();
    await tester.pumpWidget(MovePageApp(reader: _reader(u), share: share));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(OhMoveDataScreen), findsOneWidget);
    expect(find.text('Porch now lives at porch.familyflourishing.org.'),
        findsOneWidget);
    expect(find.text('We found 2 records saved in this browser.'),
        findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text(ohMoveSaveLabel));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(share.shared, hasLength(1));
    expect(share.shared.single.fileName, endsWith('.porchbackup'));
    expect(find.text(moveSavedNote), findsOneWidget);
  });

  testWidgets('with no identity there is nothing to share, and it says so',
      (tester) async {
    final u = await UiWorld.fresh();
    final share = RecordingBackupShare();
    await tester.pumpWidget(MovePageApp(reader: _reader(u), share: share));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(ohMoveSaveLabel));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(share.shared, isEmpty);
    expect(find.text(moveNothingToSave), findsOneWidget);
  });

  group('the offer on the first screen', () {
    testWidgets('onboarding in an empty browser on the web shows it, and '
        'its import opens the restore-from-file step', (tester) async {
      debugOhMovedHereOfferOnWeb = true;
      final u = await UiWorld.fresh();
      await pumpPorch(tester, u);
      expect(find.text(ohMovedHereTitle), findsOneWidget);
      await tapItem(tester, find.text(ohMovedHereImportLabel));
      expect(find.text('Restore from a backup file'), findsOneWidget);
    });

    testWidgets('off the web it shows nothing', (tester) async {
      debugOhMovedHereOfferOnWeb = false;
      final u = await UiWorld.fresh();
      await pumpPorch(tester, u);
      expect(find.text(ohMovedHereTitle), findsNothing);
    });

    test('the slot hides itself once there is an identity', () {
      expect(
          const MovedHereOfferSlot(storeIsEmpty: false, onImport: _noop)
              .storeIsEmpty,
          isFalse);
    });
  });
}

void _noop() {}

/// A secret store that counts every write and delete.
class _CountingSecrets implements SecretStore {
  final _inner = InMemorySecretStore();
  int changes = 0;
  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) {
    changes++;
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    changes++;
    return _inner.delete(key);
  }
}
