import 'package:flutter_gemma/flutter_gemma.dart';

import 'local_model.dart';

/// The one file that names flutter_gemma's model API (with `gemma_init_*`,
/// which only initialises it). It adapts flutter_gemma 0.13.x to Reckon's
/// [LocalModelRuntime]. flutter_gemma is discontinued and replaced by
/// flutter_edge_ai; moving to it means rewriting this file and the init,
/// nothing else (ADR 0010).
///
/// Native builds only: the web LLM builder never reaches it.
class GemmaRuntime implements LocalModelRuntime {
  const GemmaRuntime();

  @override
  Future<LocalModel> load({
    required String path,
    required String modelType,
    required int maxTokens,
  }) async {
    // Registers the file, already on the device, with flutter_gemma's store
    // so its runtime can open it. `fromFile` copies nothing and fetches
    // nothing.
    await FlutterGemma.installModel(modelType: gemmaModelType(modelType))
        .fromFile(path)
        .install();

    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    return GemmaLocalModel(model);
  }
}

/// A loaded flutter_gemma [InferenceModel] seen as a Reckon [LocalModel].
class GemmaLocalModel implements LocalModel {
  GemmaLocalModel(this._model);

  final InferenceModel _model;

  @override
  Future<LocalChat> openChat({
    required String systemInstruction,
    required double temperature,
    required int topK,
  }) async {
    final chat = await _model.createChat(
      systemInstruction: systemInstruction,
      temperature: temperature,
      topK: topK,
    );
    return _GemmaChat(chat);
  }

  @override
  Future<void> close() => _model.close();
}

class _GemmaChat implements LocalChat {
  _GemmaChat(this._chat);

  final InferenceChat _chat;

  @override
  Future<void> addTurn(String text, {required bool isUser}) =>
      _chat.addQueryChunk(Message.text(text: text, isUser: isUser));

  @override
  Stream<String> reply() async* {
    await for (final response in _chat.generateChatResponseAsync()) {
      if (response is TextResponse) yield response.token;
    }
  }

  /// A no-op on flutter_gemma 0.13: the model keeps one live session and the
  /// next createChat replaces it, which is how Reckon has always run.
  @override
  Future<void> close() async {}
}

/// Maps a `ReckonModelSpec.modelType` string onto flutter_gemma's
/// [ModelType]; an unknown name falls back to [ModelType.gemmaIt], as before.
ModelType gemmaModelType(String name) =>
    ModelType.values.firstWhere((t) => t.name == name,
        orElse: () => ModelType.gemmaIt);
