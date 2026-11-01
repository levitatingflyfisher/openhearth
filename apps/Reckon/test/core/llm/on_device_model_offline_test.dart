import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/llm_providers.dart';
import 'package:reckon/core/llm/local_model.dart';
import 'package:reckon/core/llm/model_download_service.dart';
import 'package:reckon/core/llm/model_spec.dart';
import 'package:reckon/features/case/domain/entities/case.dart';

/// The on-device path end to end, from the file on disk to an answer, with
/// the network switched off: any HTTP client or socket the code opens throws
/// and is counted. The model itself is a fake; no model file is opened and
/// nothing runs on a graphics card.
Future<T> _offline<T>(Future<T> Function() body, List<String> attempts) {
  Never refuse(String what) {
    attempts.add(what);
    throw SocketException('network is off in this test: $what');
  }

  return IOOverrides.runZoned(
    () => HttpOverrides.runZoned(
      body,
      createHttpClient: (_) => refuse('http client'),
    ),
    socketConnect: (host, port,
            {sourceAddress, int sourcePort = 0, Duration? timeout}) =>
        refuse('socket $host:$port'),
    socketStartConnect: (host, port, {sourceAddress, int sourcePort = 0}) =>
        refuse('socket $host:$port'),
  );
}

class _FakeRuntime implements LocalModelRuntime {
  _FakeRuntime(this.reply);
  final String reply;
  final loadedPaths = <String>[];

  @override
  Future<LocalModel> load({
    required String path,
    required String modelType,
    required int maxTokens,
  }) async {
    loadedPaths.add(path);
    return _FakeModel(reply);
  }
}

class _FakeModel implements LocalModel {
  _FakeModel(this.reply);
  final String reply;
  bool closed = false;

  @override
  Future<LocalChat> openChat({
    required String systemInstruction,
    required double temperature,
    required int topK,
  }) async =>
      _FakeChat(reply);

  @override
  Future<void> close() async => closed = true;
}

class _FakeChat implements LocalChat {
  _FakeChat(this.canned);
  final String canned;

  @override
  Future<void> addTurn(String text, {required bool isUser}) async {}

  @override
  Future<void> close() async {}

  @override
  Stream<String> reply() => Stream.fromIterable([canned]);
}

Case _case() => Case(
      id: 'c1',
      createdAt: DateTime(2026, 11, 12),
      deadline: null,
      status: CaseStatus.open,
      question: 'Move to the cabin?',
      optionA: 'Stay in town',
      optionB: 'Move',
      statedCriteria: const [],
      stakes: Stakes.high,
      regretHorizon: RegretHorizon.years,
      category: 'relocation',
    );

void main() {
  late Directory dir;
  late _FakeRuntime runtime;
  late List<String> attempts;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('reckon_offline_model_');
    runtime = _FakeRuntime('{"lean": 62, "rationale": "Most movers are glad."}');
    attempts = [];
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      selectedModelIdProvider.overrideWith((ref) async => null),
      modelDownloadServiceProvider.overrideWithValue(
        ModelDownloadService(documentsDirectory: () async => dir),
      ),
      localModelRuntimeProvider.overrideWithValue(runtime),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  File modelFileOnDisk(List<int> bytes) =>
      File('${dir.path}/${ReckonModelSpec.qwen25_1_5b.fileName}')
        ..writeAsBytesSync(bytes);

  test('the guard itself refuses and counts a connection', () async {
    await _offline(() async {
      expect(() => HttpClient(), throwsA(isA<SocketException>()));
      await expectLater(
        () => Socket.connect('example.org', 443),
        throwsA(isA<SocketException>()),
      );
    }, attempts);
    expect(attempts, hasLength(2));
  });

  test('loads the model from the file on the device and answers, offline',
      () async {
    final file = modelFileOnDisk([0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0)]);
    final c = container();

    final seed = await _offline(() async {
      final llm = await c.read(llmServiceProvider.future);
      return llm.generateCommunitySeed(_case());
    }, attempts);

    expect(runtime.loadedPaths, [file.path]);
    expect(seed.lean, 62);
    expect(seed.rationale, contains('glad'));
    expect(attempts, isEmpty, reason: 'the on-device path opened a connection');
  });

  test('a missing model file fails plainly, offline', () async {
    final c = container();
    final sub = c.listen(llmServiceProvider, (_, _) {});
    addTearDown(sub.close);

    final error = await _offline(() async {
      try {
        await c.read(llmServiceProvider.future);
        return null;
      } catch (e) {
        return e;
      }
    }, attempts);

    expect(error, isA<LocalModelFileMissing>());
    expect(runtime.loadedPaths, isEmpty);
    expect(attempts, isEmpty);
  });

  test('a broken model file fails plainly and never reaches the runtime',
      () async {
    modelFileOnDisk([0x54, 0x46, 0x4C, 0x33, 0, 0, 0, 0]); // "TFL3", no ZIP
    final c = container();
    final sub = c.listen(llmServiceProvider, (_, _) {});
    addTearDown(sub.close);

    final error = await _offline(() async {
      try {
        await c.read(llmServiceProvider.future);
        return null;
      } catch (e) {
        return e;
      }
    }, attempts);

    expect(error, isA<LocalModelFileBroken>());
    expect(runtime.loadedPaths, isEmpty);
    expect(attempts, isEmpty);
  });
}
