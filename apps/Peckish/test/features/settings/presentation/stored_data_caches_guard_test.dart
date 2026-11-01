import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';

// Erase and restore change the stored data under every provider that lives
// as long as the app. An autoDispose provider goes when its screen goes, and
// a Drift watch stream follows the database by itself; a long-lived one
// keeps whatever it read until something resets it. This test finds every
// long-lived provider in lib/ and makes each one be ruled on: either it is
// in storedDataCaches, which both paths reset, or it is listed below with
// the reason it holds no stored data. A new long-lived provider fails here
// until someone decides.

/// Long-lived, and holds a copy of stored data: reset by erase and restore.
final Map<String, ProviderOrFamily> _reset = {
  'aiConfigProvider': aiConfigProvider,
};

/// Long-lived, and holds no copy of stored data.
const Map<String, String> _holdsNoStoredData = {
  'sharedPreferencesProvider': 'the store itself, not a copy of it',
  'appRouterProvider': 'navigation only',
  'spineReadyProvider': 'the shipped food database, which erase keeps',
  'undoControllerProvider': 'a pending write; both paths end it separately',
  'aiKeyStoreProvider': 'reads secure storage on every call',
  'stoveSecretStoreProvider': 'reads secure storage on every call',
  'aiConfigRepositoryProvider': 'reads prefs and secure storage on every call',
  'guessHttpClientProvider': 'a test override point',
  'stoveBrainFactoryProvider': 'a factory',
  'modelDownloadServiceProvider': 'the model file on disk, not household data',
  'localBrainProvider': 'the loaded model; reads the model id at guess time',
  'plateScannerProvider': 'a labeler with no memory',
  'platePhotoPickerProvider': 'a function',
  'barcodeResolverProvider': 'reads saved foods at each scan; caches only '
      'open handles to the downloaded barcode database',
  'barcodeDbDownloadServiceProvider': 'the downloaded barcode database',
  'offClientProvider': 'a network client',
  'recipeDraftStoreProvider': 'reads prefs on every call; both paths clear it',
  'recipeFetcherProvider': 'a network client',
  'syncSecretStoreProvider': 'reads secure storage on every call',
  'lanSyncServerProvider': 'reads the code and the database per request; '
      'erase stops it',
};

/// Provider kinds that live as long as the app unless `.autoDispose`.
const _kinds = r'(?:Provider|FutureProvider|StreamProvider|StateProvider|'
    r'NotifierProvider|AsyncNotifierProvider|StreamNotifierProvider|'
    r'ChangeNotifierProvider|StateNotifierProvider)';

Set<String> _longLivedProvidersInLib() {
  final plain = RegExp(
      r'final\s+(\w+Provider)\s*=\s*' + _kinds + r'(?:\.family)?\s*[<(]');
  final keepAliveFn =
      RegExp(r'@Riverpod\(keepAlive: true[^)]*\)\s*\n[^\n(]*?\s(\w+)\(Ref ref');
  final keepAliveClass =
      RegExp(r'@Riverpod\(keepAlive: true[^)]*\)\s*\nclass\s+(\w+)\s');
  final found = <String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.endsWith('.g.dart')) continue;
    final src = f.readAsStringSync();
    found.addAll(plain.allMatches(src).map((m) => m[1]!));
    found.addAll(keepAliveFn.allMatches(src).map((m) => '${m[1]}Provider'));
    found.addAll(keepAliveClass
        .allMatches(src)
        .map((m) => '${m[1]![0].toLowerCase()}${m[1]!.substring(1)}Provider'));
  }
  return found;
}

void main() {
  test('every long-lived provider in lib/ is ruled on', () {
    final found = _longLivedProvidersInLib();
    expect(found, contains('aiConfigProvider'),
        reason: 'the scan must find the providers');
    expect(found, {..._reset.keys, ..._holdsNoStoredData.keys});
  });

  test('storedDataCaches is exactly the ones that hold stored data', () {
    expect(storedDataCaches.toSet(), _reset.values.toSet());
  });
}
