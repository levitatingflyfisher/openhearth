import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/core/llm/llm_service.dart';
import 'package:reckon/core/llm/local_model.dart';
import 'package:reckon/core/llm/private_mode_impl.dart';
import 'package:reckon/features/case/domain/entities/case.dart';

/// Fake chat: replays a canned reply and records the turns it was given.
class _FakeChat implements LocalChat {
  _FakeChat(this.canned, {this.failReply = false});

  final String canned;
  final bool failReply;
  final List<({String text, bool isUser})> turns = [];
  bool closed = false;

  @override
  Future<void> addTurn(String text, {required bool isUser}) async =>
      turns.add((text: text, isUser: isUser));

  @override
  Stream<String> reply() => failReply
      ? Stream.error(StateError('reply fell over'))
      : Stream.fromIterable([canned]);

  @override
  Future<void> close() async => closed = true;
}

/// Fake model behind Reckon's own [LocalModel] interface: no runtime, no
/// model file. It records the settings each chat was opened with.
class _FakeModel implements LocalModel {
  _FakeModel(this.reply, {this.throwOnSession = false, this.failReply = false});

  final String reply;
  final bool throwOnSession;
  final bool failReply;
  final List<_FakeChat> chats = [];

  String? lastSystemInstruction;
  double? lastTemperature;

  @override
  Future<LocalChat> openChat({
    required String systemInstruction,
    required double temperature,
    required int topK,
  }) async {
    if (throwOnSession) throw StateError('native runtime fell over');
    lastSystemInstruction = systemInstruction;
    lastTemperature = temperature;
    final chat = _FakeChat(reply, failReply: failReply);
    chats.add(chat);
    return chat;
  }

  @override
  Future<void> close() async {}
}

Case _case() => Case(
      id: 'c1',
      createdAt: DateTime(2026, 7, 11),
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
  test('generateCommunitySeed parses the single-line JSON reply', () async {
    final model = _FakeModel(
        '{"lean": 62, "rationale": "Most movers in this class are glad."}');
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    final seed = await svc.generateCommunitySeed(_case());

    expect(seed.lean, 62);
    expect(seed.rationale, contains('glad'));
  });

  test('clamps an out-of-range lean into 0-100', () async {
    final model = _FakeModel('{"lean": 140, "rationale": "sure"}');
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    final seed = await svc.generateCommunitySeed(_case());

    expect(seed.lean, 100);
  });

  test('persona reaches the system instruction; none means neutral prompt',
      () async {
    final model = _FakeModel('{"lean": 50, "rationale": "even"}');
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    await svc.generateCommunitySeed(
      _case(),
      persona: 'Anchors on base rates and distrusts special stories.',
    );
    expect(model.lastSystemInstruction, contains('base rates'));

    await svc.generateCommunitySeed(_case());
    expect(model.lastSystemInstruction, isNot(contains('base rates')));
    expect(model.lastSystemInstruction, contains('"lean"'));
  });

  test('temperature override reaches the session', () async {
    final model = _FakeModel('{"lean": 50, "rationale": "even"}');
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    await svc.generateCommunitySeed(_case(), temperature: 0.9);
    expect(model.lastTemperature, 0.9);

    await svc.generateCommunitySeed(_case());
    expect(model.lastTemperature, 0.4); // structured-call default
  });

  test('an unparseable reply degrades to the sentinel, never throws',
      () async {
    final model = _FakeModel('I cannot answer that in JSON, sorry.');
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    final seed = await svc.generateCommunitySeed(_case());

    expect(seed.lean, 50);
    expect(seed.rationale, isEmpty); // empty rationale marks the sentinel
  });

  test('a native failure degrades to the sentinel, never throws', () async {
    final model = _FakeModel('unused', throwOnSession: true);
    final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

    final seed = await svc.generateCommunitySeed(_case());

    expect(seed.lean, 50);
    expect(seed.rationale, isEmpty);
  });

  group('redactQuestion', () {
    test('parses the single-line JSON rewrite', () async {
      final model = _FakeModel(
          '{"title": "Buy the vacation cabin?", '
          '"background": "Family of five, single income."}');
      final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

      final r = await svc.redactQuestion(
        title: 'Buy the cabin near Bear Lake?',
        background: 'The Hansens are a family of five; Jim works at Acme.',
      );

      expect(r.isSentinel, isFalse);
      expect(r.title, 'Buy the vacation cabin?');
      expect(r.background, 'Family of five, single income.');
      // The redactor prompt reached the session.
      expect(model.lastSystemInstruction, contains('de-identify'));
    });

    test('an unparseable reply degrades to the sentinel', () async {
      final model = _FakeModel('Sure! Here is a redacted version: ...');
      final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

      final r = await svc.redactQuestion(title: 't', background: 'b');

      expect(r.isSentinel, isTrue);
    });

    test('a reply missing either field degrades to the sentinel', () async {
      final model = _FakeModel('{"title": "only a title"}');
      final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

      final r = await svc.redactQuestion(title: 't', background: 'b');

      expect(r.isSentinel, isTrue);
    });

    test('a native failure degrades to the sentinel, never throws', () async {
      final model = _FakeModel('unused', throwOnSession: true);
      final svc = PrivateModeImpl(model, 'qwen-2.5-1.5b-it');

      final r = await svc.redactQuestion(title: 't', background: 'b');

      expect(r.isSentinel, isTrue);
    });
  });

  group('every chat Reckon opens is closed', () {
    test('a structured call closes its chat', () async {
      final model = _FakeModel('{"lean": 50, "rationale": "even"}');
      await PrivateModeImpl(model, 'qwen-2.5-1.5b-it')
          .generateCommunitySeed(_case());

      expect(model.chats.single.closed, isTrue);
    });

    test('a failed reply still closes its chat', () async {
      final model = _FakeModel('unused', failReply: true);
      final seed = await PrivateModeImpl(model, 'qwen-2.5-1.5b-it')
          .generateCommunitySeed(_case());

      expect(seed.rationale, isEmpty);
      expect(model.chats.single.closed, isTrue);
    });

    test('the intake chat closes once its reply has streamed', () async {
      final model = _FakeModel('What matters most to you here?');
      final tokens = await PrivateModeImpl(model, 'qwen-2.5-1.5b-it')
          .conductIntake(const IntakeContext(
            transcript: [
              IntakeTurn(role: IntakeRole.assistant, content: 'Hello.'),
            ],
            userInput: 'Should we move?',
          ))
          .toList();

      expect(tokens.join(), 'What matters most to you here?');
      expect(model.chats.single.turns.last, (text: 'Should we move?', isUser: true));
      expect(model.chats.single.closed, isTrue);
    });
  });
}
