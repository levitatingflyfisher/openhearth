import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_unavailable.dart';
import 'llm_service.dart';
import 'local_model.dart';

/// Web: the browser build has no on-device model runtime. Screens read this
/// through `onDeviceModelSupportedProvider` rather than testing `kIsWeb`, so
/// they ask about the capability, not the platform, and cannot offer a model
/// download the build could never use.
const bool hasOnDeviceModelRuntime = false;

/// Web: no runtime loads model files. Nothing reaches this in practice; it
/// fails with the same typed [AiUnavailableOnWeb] as [buildLlmService].
LocalModelRuntime defaultLocalModelRuntime() => const _NoLocalModelRuntime();

class _NoLocalModelRuntime implements LocalModelRuntime {
  const _NoLocalModelRuntime();

  @override
  Future<LocalModel> load({
    required String path,
    required String modelType,
    required int maxTokens,
  }) async =>
      throw const AiUnavailableOnWeb();
}

/// Web: there is no on-device model and no configured cloud backend, so any
/// attempt to build an LLM service fails with a typed, catchable
/// [AiUnavailableOnWeb]. AI entry points gate on
/// `onDeviceModelSupportedProvider` before reaching this, so in practice it is
/// a backstop rather than a hot path. Nothing here imports flutter_gemma.
Future<LlmService> buildLlmService(Ref ref) async {
  throw const AiUnavailableOnWeb();
}
