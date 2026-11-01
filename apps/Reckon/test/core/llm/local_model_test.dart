import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/local_model.dart';
import 'package:reckon/core/llm/local_model_loader.dart';

/// A runtime that never touches a native library: it records what it was
/// asked to load and hands back a model whose chats replay a canned reply.
class _FakeRuntime implements LocalModelRuntime {
  _FakeRuntime({this.reply = 'ok', this.failWith});

  final String reply;
  final Object? failWith;
  final loads = <({String path, String modelType, int maxTokens})>[];

  @override
  Future<LocalModel> load({
    required String path,
    required String modelType,
    required int maxTokens,
  }) async {
    loads.add((path: path, modelType: modelType, maxTokens: maxTokens));
    if (failWith != null) throw failWith!;
    return _FakeModel(reply);
  }
}

class _FakeModel implements LocalModel {
  _FakeModel(this.reply);
  final String reply;

  @override
  Future<LocalChat> openChat({
    required String systemInstruction,
    required double temperature,
    required int topK,
  }) async =>
      _FakeChat(reply);

  @override
  Future<void> close() async {}
}

class _FakeChat implements LocalChat {
  _FakeChat(this.canned);
  final String canned;

  @override
  Future<void> addTurn(String text, {required bool isUser}) async {}

  @override
  Future<void> close() async {}

  @override
  Stream<String> reply() => Stream.value(canned);
}

/// The first bytes of a ZIP archive, which is what a MediaPipe `.task`
/// bundle is. The rest of the file is filler: no real model is opened.
const _zipMagic = [0x50, 0x4B, 0x03, 0x04];

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('reckon_local_model_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File taskFile(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('loads a .task file from the device and passes the runtime its path',
      () async {
    final file = taskFile('m.task', [..._zipMagic, ...List.filled(64, 0)]);
    final runtime = _FakeRuntime(reply: 'hello');

    final model = await loadLocalModel(
      runtime,
      file,
      modelType: 'qwen',
      maxTokens: 4096,
    );

    expect(runtime.loads.single.path, file.path);
    expect(runtime.loads.single.modelType, 'qwen');
    expect(runtime.loads.single.maxTokens, 4096);
    final chat = await model.openChat(
        systemInstruction: 's', temperature: 0.4, topK: 20);
    expect(await chat.reply().join(), 'hello');
  });

  test('a missing file fails plainly and never reaches the runtime', () async {
    final runtime = _FakeRuntime();
    final missing = File('${dir.path}/absent.task');

    await expectLater(
      loadLocalModel(runtime, missing, modelType: 'qwen', maxTokens: 4096),
      throwsA(isA<LocalModelFileMissing>()
          .having((e) => e.path, 'path', missing.path)),
    );
    expect(runtime.loads, isEmpty);
  });

  test('an empty file is broken and never reaches the runtime', () async {
    final runtime = _FakeRuntime();
    final empty = taskFile('empty.task', const []);

    await expectLater(
      loadLocalModel(runtime, empty, modelType: 'qwen', maxTokens: 4096),
      throwsA(isA<LocalModelFileBroken>()),
    );
    expect(runtime.loads, isEmpty);
  });

  test('a .task file that is not a ZIP bundle is broken', () async {
    // "TFL3" is a raw LiteRT flatbuffer: the very file that once died inside
    // the native runtime with "unable to open zip archive".
    final runtime = _FakeRuntime();
    final tfl3 = taskFile('raw.task', [0x54, 0x46, 0x4C, 0x33, 0, 0, 0, 0]);

    await expectLater(
      loadLocalModel(runtime, tfl3, modelType: 'qwen', maxTokens: 4096),
      throwsA(isA<LocalModelFileBroken>()),
    );
    expect(runtime.loads, isEmpty);
  });

  test('a file of a format Reckon does not know is refused, not guessed',
      () async {
    final runtime = _FakeRuntime();
    final odd = taskFile('m.bin', [..._zipMagic, 0, 0]);

    await expectLater(
      loadLocalModel(runtime, odd, modelType: 'qwen', maxTokens: 4096),
      throwsA(isA<LocalModelFileBroken>()),
    );
    expect(runtime.loads, isEmpty);
  });

  test('a runtime failure comes back as one plain error that keeps the cause',
      () async {
    final cause = StateError('native runtime fell over');
    final runtime = _FakeRuntime(failWith: cause);
    final file = taskFile('m.task', [..._zipMagic, 0, 0]);

    await expectLater(
      loadLocalModel(runtime, file, modelType: 'qwen', maxTokens: 4096),
      throwsA(isA<LocalModelStartFailed>()
          .having((e) => e.cause, 'cause', same(cause))
          .having((e) => e.toString(), 'message',
              isNot(contains('fell over')))),
    );
  });

  test('every load error is one LocalModelLoadError with a plain sentence',
      () {
    final errors = <LocalModelLoadError>[
      const LocalModelFileMissing('/x/m.task'),
      const LocalModelFileBroken('/x/m.task', 'not a ZIP bundle'),
      LocalModelStartFailed(StateError('boom')),
    ];
    for (final e in errors) {
      expect(e.message, isNotEmpty);
      expect(e.message, isNot(contains('boom')));
    }
  });
}
