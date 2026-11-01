import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
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

/// board-0166, board-0170: the household sees who publishes the app, in the
/// fleet's one shared line (the words live in openhearth_design).
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('About names the publisher', (tester) async {
    // A tall screen, so the lazy list builds the whole page.
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onDeviceModelSupportedProvider.overrideWithValue(false),
          modelDownloadServiceProvider.overrideWithValue(_NothingDownloaded()),
          forecasterRepositoryProvider.overrideWithValue(
            InMemoryForecasterRepository(const []),
          ),
          runnableForecastersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Published by Intergenerational Symbolic Systems'),
      findsOneWidget,
    );
    expect(find.byType(OhPublisherLine), findsOneWidget);
  });
}
