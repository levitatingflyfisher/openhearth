/// Reckon's own words for the on-device model, so no file outside the one
/// runtime adapter names a model package. `PrivateModeImpl` speaks only
/// these three types; the adapter (today `gemma_runtime.dart`, over
/// flutter_gemma) is the one file a runtime change rewrites. See ADR 0010.
///
/// Pure Dart, no `dart:io`, so the web builder can name it too. The file
/// check that needs `dart:io` is `local_model_loader.dart`.
abstract interface class LocalModelRuntime {
  /// Loads the model file at [path], already on the device and already
  /// checked by `loadLocalModel`. [modelType] is the
  /// `ReckonModelSpec.modelType` string; [maxTokens] caps the whole context
  /// (system prompt, conversation and reply). Never fetches anything.
  Future<LocalModel> load({
    required String path,
    required String modelType,
    required int maxTokens,
  });
}

/// A loaded on-device model. One resident model serves every call; each
/// call opens its own chat with its own system instruction and sampling.
abstract interface class LocalModel {
  Future<LocalChat> openChat({
    required String systemInstruction,
    required double temperature,
    required int topK,
  });

  /// Frees the native model. Called when the LLM provider is disposed.
  Future<void> close();
}

/// One conversation with a [LocalModel].
abstract interface class LocalChat {
  /// Adds one turn of the conversation, the person's or the model's.
  Future<void> addTurn(String text, {required bool isUser});

  /// Streams the model's reply to the turns so far, text only.
  Stream<String> reply();

  /// Ends the conversation and frees what it holds. Every caller closes
  /// each chat it opens, success or failure.
  Future<void> close();
}

/// Why the on-device model could not be loaded. Every case carries a plain
/// [message]; the cause of a runtime failure is kept for the log, never put
/// in the sentence (fleet error ruling).
sealed class LocalModelLoadError implements Exception {
  const LocalModelLoadError();

  /// One plain sentence. Never contains exception text.
  String get message;

  @override
  String toString() => message;
}

/// The model file is not on the device.
final class LocalModelFileMissing extends LocalModelLoadError {
  const LocalModelFileMissing(this.path);
  final String path;

  @override
  String get message => 'The on-device model file is not on this device.';
}

/// The file is there but is not a model file Reckon can load: empty, the
/// wrong format, or a format Reckon does not know. Caught before the native
/// runtime sees it, so a bad file never crashes inside native code.
final class LocalModelFileBroken extends LocalModelLoadError {
  const LocalModelFileBroken(this.path, this.reason);
  final String path;

  /// What was wrong, for the log.
  final String reason;

  @override
  String get message =>
      'The on-device model file is damaged or of a kind Reckon cannot load.';
}

/// The file looked right but the runtime failed to start it (low memory, a
/// device the runtime does not support, a runtime bug).
final class LocalModelStartFailed extends LocalModelLoadError {
  LocalModelStartFailed(this.cause);

  /// The runtime's own error, for the log only.
  final Object cause;

  @override
  String get message => 'The on-device model could not start.';
}
