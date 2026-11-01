// Platform-selected LLM service factory. The native variant loads the selected
// on-device model through the native runtime adapter (`gemma_runtime.dart`);
// the web variant throws a catchable [AiUnavailableOnWeb] because the browser
// build has no model runtime. Keeping the runtime-dependent construction
// behind `dart.library.io` means a web build never references the model
// package. Both variants expose `Future<LlmService> buildLlmService(Ref ref)`,
// `LocalModelRuntime defaultLocalModelRuntime()` and the matching
// `const bool hasOnDeviceModelRuntime`, the capability screens gate on.
export 'llm_service_builder_web.dart'
    if (dart.library.io) 'llm_service_builder_native.dart';
