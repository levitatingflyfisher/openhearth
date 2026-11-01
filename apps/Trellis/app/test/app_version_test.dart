import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trellis/app_version.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = line.substring('version:'.length).trim().split('+').first;
    expect(appVersion, version);
  });

  test('User-Agent uses the standard Firefox string with no app leak', () {
    expect(
      trellisUserAgent,
      'Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0',
    );
    expect(trellisUserAgent.toLowerCase(), isNot(contains('trellis')));
    expect(trellisUserAgent, isNot(contains(appVersion)));
    expect(trellisUserAgent.toLowerCase(), isNot(contains('github')));
    expect(trellisUserAgent, isNot(contains('Dart')));
  });
}
