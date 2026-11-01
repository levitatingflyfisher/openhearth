// A restore or a hatcher's removal changes the database under every
// long-lived provider. This guard holds the line for the whole class: each
// keepAlive provider in lib/ is either in storedDataCaches, which both paths
// reset, or named as holding no stored data. A new keepAlive cache cannot
// slip past both lists unseen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/providers/stored_data_caches.dart';

/// `@Riverpod(keepAlive: true)` (any other arguments allowed), then the
/// function or class it annotates. The generated provider is that name in
/// lower camel case plus `Provider`.
final _keepAlive = RegExp(
  r'@Riverpod\([^)]*keepAlive:\s*true[^)]*\)\s*'
  r'(?:class\s+(\w+)|[\w<>?, ]+?\s+(\w+)\s*\()',
);

String _providerName(String declared) =>
    '${declared[0].toLowerCase()}${declared.substring(1)}Provider';

void main() {
  test('every keepAlive provider in lib/ is reset by erase and restore, or '
      'is named as holding no stored data', () {
    final found = <String>{};
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in sources) {
      for (final m in _keepAlive.allMatches(file.readAsStringSync())) {
        found.add(_providerName(m.group(1) ?? m.group(2)!));
      }
    }
    // An empty scan means the pattern broke, not that all is well.
    expect(found, contains('engineServiceProvider'));

    final listed = {
      for (final p in [...storedDataCaches, ...keepAliveWithoutStoredData])
        p.name,
    };
    expect(
      found.difference(listed),
      isEmpty,
      reason:
          'add each to storedDataCaches if it holds stored data, '
          'else to keepAliveWithoutStoredData',
    );
    expect(
      listed.difference(found),
      isEmpty,
      reason: 'a listed provider is no longer keepAlive in lib/',
    );
  });

  test('the reset forgets exactly the stored-data caches', () {
    final forgotten = <String?>[];
    forgetCachedData((p) => forgotten.add(p.name));
    expect(forgotten, [for (final p in storedDataCaches) p.name]);
  });
}
