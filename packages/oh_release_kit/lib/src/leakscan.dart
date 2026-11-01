/// The leak scan: what a release diff adds, checked for anything private
/// before a public push (release habit 5).
///
/// The generic checks live here, in public. Every private word (people's
/// names, personal domains, family words) comes only from a patterns file
/// the caller keeps outside the repo, so this code never holds one.
library;

/// One added line. [line] is the line number in the new file, or null for
/// the new file's path itself (a file name can leak as well as its text).
class AddedLine {
  final String path;
  final int? line;
  final String text;
  const AddedLine(this.path, this.line, this.text);
}

class LeakRule {
  final String name;
  final RegExp pattern;

  /// Matches that are not leaks, such as the persona's own address.
  final bool Function(String match)? allow;

  const LeakRule(this.name, this.pattern, {this.allow});
}

class LeakHit {
  final AddedLine at;
  final String rule;
  const LeakHit(this.at, this.rule);
}

final _hunk = RegExp(r'^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

/// The added lines of a unified diff, with their paths and line numbers.
///
/// Hunk line counts decide where a hunk ends, so an added line that itself
/// starts with `++` or `--` is never mistaken for a file header.
/// With [allLines], every line of [text] counts as added: for scanning
/// commit messages or any plain file.
List<AddedLine> addedLines(String text, {bool allLines = false}) {
  final lines = text.split('\n');
  if (allLines) {
    return [
      for (var i = 0; i < lines.length; i++) AddedLine('-', i + 1, lines[i]),
    ];
  }
  final out = <AddedLine>[];
  String? path;
  var oldLeft = 0, newLeft = 0, newLine = 0;
  for (final l in lines) {
    if (oldLeft > 0 || newLeft > 0) {
      if (l.startsWith('+')) {
        out.add(AddedLine(path ?? '?', newLine++, l.substring(1)));
        newLeft--;
      } else if (l.startsWith('-')) {
        oldLeft--;
      } else if (l.startsWith(' ') || l.isEmpty) {
        // Some tools strip the space of an empty context line.
        newLine++;
        oldLeft--;
        newLeft--;
      }
      // A "\ No newline at end of file" marker counts against neither side.
      continue;
    }
    if (l.startsWith('diff ')) {
      path = null;
    } else if (l.startsWith('+++ ')) {
      final p = l.substring(4).split('\t').first;
      if (p == '/dev/null') {
        path = null;
      } else {
        // b/ is git's default prefix; i/, w/, c/ and o/ are its mnemonic
        // ones (diff.mnemonicPrefix) for index, work tree, commit, object.
        path = p.replaceFirst(RegExp(r'^[biwco]/'), '');
        out.add(AddedLine(path, null, path));
      }
    } else {
      final m = _hunk.firstMatch(l);
      if (m != null) {
        oldLeft = int.parse(m.group(1) ?? '1');
        newLine = int.parse(m.group(2)!);
        newLeft = int.parse(m.group(3) ?? '1');
      }
    }
  }
  return out;
}

// The persona's noreply address is public by design: it is the commit
// author of every fleet repo. Built from parts so this file does not trip
// a scan that lacks this allowance.
const _personaAddress =
    '90985475+levitatingflyfisher'
    '@'
    'users.noreply.github.com';

const _githubRemote =
    'git'
    '@'
    'github.com';

bool _allowedEmail(String m) {
  final lower = m.toLowerCase();
  if (lower == _personaAddress) return true;
  // An SSH remote, not a person.
  if (lower == _githubRemote) return true;
  // The domains set aside for examples (RFC 2606) reach nobody.
  return RegExp(r'@(?:[\w-]+\.)*example\.(?:com|org|net)$').hasMatch(lower);
}

/// The generic checks. Slashes are escaped and words split in the
/// patterns below so that this file's own text does not match them.
final List<LeakRule> publicLeakRules = [
  LeakRule(
    'home path',
    RegExp(
      r'(?:\/home|\/Users)\/[a-z_][\w.-]*\/|[A-Za-z]:\\Users\\[^\\\s]+'
      r'|\/tmp\/clau[d]e',
    ),
  ),
  LeakRule(
    'email',
    // The domain must start with a letter, so a scaled asset name (an icon
    // name, the at sign, then 2x.png) is not an address.
    RegExp(
      r'[\w.+-]+@[a-z][\w-]*(?:\.[\w-]+)*\.[a-z]{2,}',
      caseSensitive: false,
    ),
    allow: _allowedEmail,
  ),
  LeakRule(
    'attribution',
    RegExp(
      r'co-?authored-by|generated\s+with|clau[d]e\.ai',
      caseSensitive: false,
    ),
  ),
  LeakRule(
    'machine detail',
    RegExp(
      r'\b\d+(?:\.\d+)?\s?(?:GB|GiB|TB|MB)\s+(?:of\s+)?(?:RAM|memory|VRAM|swap)\b'
      r'|\b\d+[- ]?cores?\b'
      r'|\b(?:RT|GT)X\s?\d{3,4}\b'
      r'|\b(?:R[y]zen|Threadr[i]pper|X[e]on|GeF[o]rce|Rad[e]on|Quadr[o])\b'
      r'|\bCore\s+i[3579]\b'
      r'|\bload\s+average\b',
      caseSensitive: false,
    ),
  ),
  LeakRule(
    'token',
    RegExp(
      r'\bgh[opsu]_[A-Za-z0-9]{20,}'
      r'|\bgithub_pat_[A-Za-z0-9_]{20,}'
      r'|\bsk-[A-Za-z0-9_-]{20,}'
      r'|\bAKIA[0-9A-Z]{16}\b'
      r'|\bAIza[0-9A-Za-z_-]{35}'
      r'|\bxox[abprs]-[A-Za-z0-9-]{10,}'
      r'|BEGIN [A-Z ]*PRIVATE KEY',
    ),
  ),
];

/// Reads a private patterns file: one regular expression per line, `#`
/// starts a comment line, blank lines are skipped. A pattern that begins
/// with `(?i)` ignores case (Dart has no inline flags, so the prefix is
/// read here). A pattern that does not compile is an error, never a skip:
/// a silently dropped pattern would let its words through.
List<LeakRule> parsePrivatePatterns(String text) {
  final rules = <LeakRule>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var source = lines[i].trim();
    if (source.isEmpty || source.startsWith('#')) continue;
    var ignoreCase = false;
    if (source.startsWith('(?i)')) {
      ignoreCase = true;
      source = source.substring(4);
    }
    // The rule is named by its line, never by its text: the report may be
    // pasted somewhere public, and the pattern is the private word.
    final name = 'private pattern (line ${i + 1})';
    try {
      rules.add(LeakRule(name, RegExp(source, caseSensitive: !ignoreCase)));
    } on FormatException catch (e) {
      throw FormatException('$name does not compile: ${e.message}');
    }
  }
  return rules;
}

/// Every hit of [rules] in the added lines of [diff].
List<LeakHit> scanDiff(
  String diff,
  List<LeakRule> rules, {
  bool allLines = false,
}) => scanLines(addedLines(diff, allLines: allLines), rules);

List<LeakHit> scanLines(List<AddedLine> lines, List<LeakRule> rules) {
  final hits = <LeakHit>[];
  for (final l in lines) {
    for (final r in rules) {
      final allow = r.allow;
      final found = r.pattern
          .allMatches(l.text)
          .any((m) => allow == null || !allow(m.group(0)!));
      if (found) hits.add(LeakHit(l, r.name));
    }
  }
  return hits;
}

/// The plain report: a count per rule, then one line per hit.
String renderLeakReport(
  List<AddedLine> lines,
  List<LeakRule> rules,
  List<LeakHit> hits,
) {
  final body = lines.where((l) => l.line != null).length;
  final files = lines.map((l) => l.path).toSet().length;
  final out = <String>['added lines: $body in $files files'];
  for (final r in rules) {
    out.add('  ${r.name}: ${hits.where((h) => h.rule == r.name).length}');
  }
  for (final h in hits) {
    final where = h.at.line == null
        ? '${h.at.path} (path)'
        : '${h.at.path}:${h.at.line}';
    var text = h.at.text.trim();
    if (text.length > 160) text = '${text.substring(0, 160)}...';
    out.add('HIT  $where: ${h.rule}: $text');
  }
  out.add(hits.isEmpty ? 'clean' : '${hits.length} hits');
  return out.join('\n');
}
