import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/llm_providers.dart';
import 'package:reckon/core/llm/model_download_service.dart';
import 'package:reckon/core/llm/model_spec.dart';
import 'package:reckon/features/forecasters/data/forecaster_providers.dart';
import 'package:reckon/features/record/presentation/settings_screen.dart';

import '../../forecasters/in_memory_fakes.dart';

class _NothingDownloaded extends ModelDownloadService {
  @override
  Future<bool> isDownloaded(ReckonModelSpec spec) async => false;
}

/// Android backup to Google is the phone owner's choice again, so Settings
/// says so next to the encrypted backup, and no longer claims that nothing
/// ever leaves the phone. The apostrophes are the typographic ones the house
/// style requires (test/shared/copy_typography_test.dart).
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Settings tells the owner Android may back up to Google',
      (tester) async {
    // A tall screen, so the lazy list builds the whole page.
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        onDeviceModelSupportedProvider.overrideWithValue(false),
        modelDownloadServiceProvider.overrideWithValue(_NothingDownloaded()),
        forecasterRepositoryProvider
            .overrideWithValue(InMemoryForecasterRepository(const [])),
        runnableForecastersProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
          'Android may also back up this app’s data to Google, if the '
          'phone’s owner allows it in Android settings. The encrypted '
          'backup here is the private choice.'),
      findsOneWidget,
    );
    // The old claim is no longer true.
    expect(find.text('None. Everything stays on this device.'), findsNothing);
  });
}
