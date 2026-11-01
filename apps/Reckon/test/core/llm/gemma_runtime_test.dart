import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/gemma_runtime.dart';

/// Fake session: replays a canned reply through the REAL flutter_gemma
/// [InferenceChat] machinery (token accounting, history), so this test runs
/// the same plumbing the phone uses, minus the native runtime.
class _FakeSession implements InferenceModelSession {
  _FakeSession(this.reply);

  final String reply;
  final List<Message> queries = [];
  bool closed = false;

  @override
  Future<void> addQueryChunk(Message message) async => queries.add(message);

  @override
  Future<String> getResponse() async => reply;

  @override
  Stream<String> getResponseAsync() => Stream.fromIterable([reply]);

  @override
  Future<int> sizeInTokens(String text) async => 1;

  @override
  Future<void> stopGeneration() async {}

  @override
  Future<void> close() async => closed = true;
}

class _FakeInferenceModel extends InferenceModel {
  _FakeInferenceModel(this.reply);

  final String reply;
  _FakeSession? lastSession;
  String? lastSystemInstruction;
  double? lastTemperature;
  int? lastTopK;
  bool closed = false;

  @override
  InferenceModelSession? get session => lastSession;

  @override
  int get maxTokens => 4096;

  @override
  ModelFileType get fileType => ModelFileType.task;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
  }) async {
    lastSystemInstruction = systemInstruction;
    lastTemperature = temperature;
    lastTopK = topK;
    return lastSession = _FakeSession(reply);
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('a chat carries its settings to the runtime and streams the reply',
      () async {
    final inference = _FakeInferenceModel('{"lean": 62}');
    final model = GemmaLocalModel(inference);

    final chat = await model.openChat(
      systemInstruction: 'You are a forecaster.',
      temperature: 0.9,
      topK: 20,
    );
    await chat.addTurn('Earlier answer', isUser: false);
    await chat.addTurn('Should we move?', isUser: true);
    final text = await chat.reply().join();

    expect(inference.lastSystemInstruction, 'You are a forecaster.');
    expect(inference.lastTemperature, 0.9);
    expect(inference.lastTopK, 20);
    expect(text, '{"lean": 62}');
    final sent = inference.lastSession!.queries;
    expect(sent.map((m) => m.text), contains('Should we move?'));
    expect(sent.where((m) => m.text == 'Should we move?').single.isUser, true);
  });

  test('closing the model closes the runtime model', () async {
    final inference = _FakeInferenceModel('');
    await GemmaLocalModel(inference).close();
    expect(inference.closed, isTrue);
  });

  test('a model type Reckon names maps onto flutter_gemma, unknown is gemmaIt',
      () {
    expect(gemmaModelType('qwen'), ModelType.qwen);
    expect(gemmaModelType('phi'), ModelType.phi);
    expect(gemmaModelType('no-such-type'), ModelType.gemmaIt);
  });

  test('closing a chat leaves flutter_gemma 0.13 its one session', () async {
    // flutter_gemma 0.13 keeps one live session per model and the next
    // createChat replaces it, so a chat's close is a no-op here. The
    // flutter_edge_ai adapter will close each detached chat for real.
    final inference = _FakeInferenceModel('ok');
    final chat = await GemmaLocalModel(inference)
        .openChat(systemInstruction: 's', temperature: 0.4, topK: 20);
    await chat.addTurn('hi', isUser: true);
    await chat.reply().join();
    await chat.close();

    expect(inference.lastSession!.closed, isFalse);
  });
}
