import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:test/test.dart';

// Every fixture that should trip a check is built from split literals, so
// this file's own text never trips the scan when a release diff holds it.
const _home =
    '/ho'
    'me/examplename/code/app';
const _email =
    'someone'
    '@'
    'exampledomain.org';
const _persona =
    '90985475+levitatingflyfisher'
    '@'
    'users.noreply.github.com';
const _trailer =
    'Co-'
    'Authored-By: A Bot <bot'
    '@'
    'exampledomain.org>';

String _diff(List<String> added, {String path = 'lib/a.dart'}) => [
  'diff --git a/$path b/$path',
  'index 1111111..2222222 100644',
  '--- a/$path',
  '+++ b/$path',
  '@@ -1,2 +1,${added.length + 1} @@',
  ' unchanged line',
  for (final a in added) '+$a',
  '-a removed line',
].join('\n');

List<String> _rules(String diff, {String private = ''}) => scanDiff(diff, [
  ...publicLeakRules,
  ...parsePrivatePatterns(private),
]).map((h) => h.rule).toList();

void main() {
  group('addedLines', () {
    test('only added lines, with the new path and line number', () {
      final lines = addedLines(_diff(['first', 'second']));
      final body = lines.where((l) => l.line != null).toList();
      expect(body.map((l) => l.text), ['first', 'second']);
      expect(body.map((l) => l.line), [2, 3]);
      expect(body.first.path, 'lib/a.dart');
    });

    test('the new file path is scanned once, as line null', () {
      final lines = addedLines(_diff(['x'], path: 'docs/notes.md'));
      expect(lines.where((l) => l.line == null).single.text, 'docs/notes.md');
    });

    test('an added line that starts with ++ is still an added line', () {
      final lines = addedLines(_diff(['++counter;']));
      expect(lines.map((l) => l.text), contains('++counter;'));
    });

    test('removed and context lines are not scanned', () {
      final texts = addedLines(_diff(['x'])).map((l) => l.text);
      expect(texts, isNot(contains('a removed line')));
      expect(texts, isNot(contains('unchanged line')));
    });

    test("git's mnemonic prefixes are stripped from the path", () {
      final diff = _diff(['x']).replaceAll('+++ b/', '+++ i/');
      expect(addedLines(diff).first.path, 'lib/a.dart');
    });

    test('a processor model word', () {
      expect(
        _rules(
          _diff([
            'on a Ry'
                'zen box',
          ]),
        ),
        ['machine detail'],
      );
    });

    test('a deleted file has no path line', () {
      const diff =
          'diff --git a/x b/x\n--- a/x\n+++ /dev/null\n'
          '@@ -1 +0,0 @@\n-gone\n';
      expect(addedLines(diff), isEmpty);
    });

    test('allLines mode scans every line of plain text', () {
      final lines = addedLines('one\ntwo', allLines: true);
      expect(lines.map((l) => l.text), ['one', 'two']);
      expect(lines.map((l) => l.line), [1, 2]);
    });
  });

  group('public rules', () {
    test('a home path', () {
      expect(_rules(_diff(['see $_home'])), ['home path']);
    });

    test('a temporary agent folder', () {
      expect(
        _rules(
          _diff([
            '/tm'
                'p/clau'
                'de-1000/x',
          ]),
        ),
        ['home path'],
      );
    });

    test('an email address', () {
      expect(_rules(_diff(['mail $_email'])), ['email']);
    });

    test('the persona address is allowed', () {
      expect(_rules(_diff(['author $_persona'])), isEmpty);
    });

    test('example domains and image scale suffixes are not emails', () {
      expect(
        _rules(
          _diff([
            'you'
                '@'
                'example.com',
            'assets/icon'
                '@'
                '2x.png',
          ]),
        ),
        isEmpty,
      );
    });

    test('an attribution trailer and its address', () {
      expect(
        _rules(_diff([_trailer])),
        unorderedEquals(['attribution', 'email']),
      );
    });

    test('a generated-with footer', () {
      expect(
        _rules(
          _diff([
            'Gene'
                'rated with a tool',
          ]),
        ),
        ['attribution'],
      );
    });

    test('the assistant site', () {
      expect(
        _rules(
          _diff([
            'https://clau'
                'de.ai/x',
          ]),
        ),
        ['attribution'],
      );
    });

    test('machine details', () {
      expect(
        _rules(
          _diff([
            'built on 64 '
                'GB of RAM',
          ]),
        ),
        ['machine detail'],
      );
      expect(
        _rules(
          _diff([
            'a 16-'
                'core box',
          ]),
        ),
        ['machine detail'],
      );
      expect(
        _rules(
          _diff([
            'an RT'
                'X 4090',
          ]),
        ),
        ['machine detail'],
      );
      expect(
        _rules(
          _diff([
            'load '
                'average 3.1',
          ]),
        ),
        ['machine detail'],
      );
    });

    test('tokens and private keys', () {
      expect(
        _rules(
          _diff([
            'gh'
                'p_${'a' * 36}',
          ]),
        ),
        ['token'],
      );
      expect(
        _rules(
          _diff([
            's'
                'k-${'b' * 30}',
          ]),
        ),
        ['token'],
      );
      expect(
        _rules(
          _diff([
            '-----BEGIN '
                'RSA PRIVATE KEY-----',
          ]),
        ),
        ['token'],
      );
    });

    test('ordinary code passes', () {
      expect(
        _rules(
          _diff([
            "import 'package:path/path.dart' as p;",
            '@override',
            'final cores = Platform.numberOfProcessors;',
          ]),
        ),
        isEmpty,
      );
    });
  });

  group('private patterns', () {
    test('one pattern per line; comments and blanks skipped', () {
      final rules = parsePrivatePatterns(
        '# a comment\n\nexamplename\n  \n\\bexamplepet\\b\n',
      );
      expect(rules.length, 2);
      expect(rules.first.name, 'private pattern (line 3)');
      expect(rules.last.name, 'private pattern (line 5)');
    });

    test('a private word hits; case matters by default', () {
      const private = 'Examplename\n';
      expect(_rules(_diff(['hi Examplename']), private: private), [
        'private pattern (line 1)',
      ]);
      expect(_rules(_diff(['hi examplename']), private: private), isEmpty);
    });

    test('a leading (?i) makes the pattern ignore case', () {
      expect(
        _rules(_diff(['EXAMPLE FAMILY']), private: '(?i)example family\n'),
        ['private pattern (line 1)'],
      );
    });

    test('a private word in a new file path hits', () {
      expect(
        _rules(
          _diff(['x'], path: 'docs/examplename.md'),
          private: 'examplename\n',
        ),
        ['private pattern (line 1)'],
      );
    });

    test('a bad pattern is an error that names its line, not a skip', () {
      expect(
        () => parsePrivatePatterns('ok\n(unclosed\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line 2'),
          ),
        ),
      );
    });
  });

  group('renderLeakReport', () {
    test('counts per rule and one line per hit, never the private pattern', () {
      final rules = [
        ...publicLeakRules,
        ...parsePrivatePatterns('exam[p]lename\n'),
      ];
      final diff = _diff(['hi examplename', 'see $_home']);
      final report = renderLeakReport(
        addedLines(diff),
        rules,
        scanDiff(diff, rules),
      );
      expect(report, contains('added lines: 2'));
      expect(report, contains('home path: 1'));
      expect(report, contains('lib/a.dart:2: private pattern (line 1)'));
      expect(report, isNot(contains('exam[p]lename')));
    });
  });
}
