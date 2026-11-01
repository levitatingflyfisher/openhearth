import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gemma_runtime.dart';
import 'llm_providers.dart';
import 'llm_service.dart';
import 'local_model.dart';
import 'local_model_loader.dart';
import 'private_mode_impl.dart';

/// Native: this build can load and run a downloaded model on the device.
const bool hasOnDeviceModelRuntime = true;

/// Native: the runtime that loads model files. Read through
/// `localModelRuntimeProvider`, which tests override with a fake.
LocalModelRuntime defaultLocalModelRuntime() => const GemmaRuntime();

/// Native: resolve the selected [ReckonModelSpec], check its file on disk,
/// load it through the [LocalModelRuntime] and wrap the result in
/// [PrivateModeImpl].
///
/// Loading the model takes several seconds and pins the file on disk, so the
/// caller's provider is kept alive across route changes (Home → Learn →
/// Home) rather than torn down.
///
/// Throws a [LocalModelLoadError] when the file is missing or broken or the
/// runtime cannot start it. UI gates on [ModelDownloadService.isDownloaded]
/// before triggering this.
Future<LlmService> buildLlmService(Ref ref) async {
  ref.keepAlive();

  final spec = ref.watch(activeModelSpecProvider);
  final downloadService = ref.watch(modelDownloadServiceProvider);
  final runtime = ref.watch(localModelRuntimeProvider);

  final file = await downloadService.modelFile(spec);

  // maxTokens caps the whole context (system prompt + conversation +
  // reply). 1024 was far too small for a multi-turn intake: the system prompt
  // plus a couple of exchanges overran it, and the model would return
  // empty/garbled output ("stops responding after a turn or two"). 4096
  // gives the small model room for the full interview.
  final model = await loadLocalModel(
    runtime,
    file,
    modelType: spec.modelType,
    maxTokens: 4096,
  );

  ref.onDispose(() async {
    await model.close();
  });

  return PrivateModeImpl(model, spec.id);
}
