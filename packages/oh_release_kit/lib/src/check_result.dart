/// What one check found. A failure makes the command exit 1; a note is
/// printed for the release ledger and changes nothing.
class CheckResult {
  final List<String> passes = [];
  final List<String> failures = [];
  final List<String> notes = [];

  bool get ok => failures.isEmpty;

  /// The plain text a command prints: one line per finding, failures last
  /// so they are what the eye lands on.
  String render() => [
    for (final p in passes) 'ok    $p',
    for (final n in notes) 'note  $n',
    for (final f in failures) 'FAIL  $f',
  ].join('\n');
}
