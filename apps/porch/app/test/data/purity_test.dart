// W3-data: structural layering test, mirroring the domain purity test.
//
// lib/data may use dart:io (files, HTTP) — that is its job — but must stay
// FLUTTER-free so the whole data layer runs on the host VM. The single
// exception is the secure-storage adapter, which is nothing but glue to the
// flutter_secure_storage plugin (it stays a leaf: nothing else may import
// it). Widget/UI packages are W4/W5 and must never appear here.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final dataDir = Directory('lib/data');

  test('lib/data exists and is non-trivial', () {
    expect(dataDir.existsSync(), isTrue);
    expect(
        dataDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .length,
        greaterThanOrEqualTo(8));
  });

  test('no Flutter/UI imports anywhere in the data layer (adapter excepted)',
      () {
    const adapterName = 'secure_storage_adapter.dart';
    final offenders = <String>[];
    for (final f in dataDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final isAdapter = f.path.endsWith(adapterName);
      for (final line in f.readAsLinesSync()) {
        final t = line.trim();
        if (!t.startsWith('import ')) continue;
        final forbidden = [
          'package:flutter/',
          'dart:ui',
          'package:home_widget/',
          'package:workmanager/',
        ];
        if (!isAdapter) forbidden.add('package:flutter_secure_storage/');
        for (final bad in forbidden) {
          if (t.contains(bad)) offenders.add('${f.path}: $t');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'data layer must stay host-VM testable:\n${offenders.join('\n')}');
  });

  test('the adapter is a leaf: no data file imports it', () {
    for (final f in dataDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('secure_storage_adapter.dart')) continue;
      final imports = f
          .readAsLinesSync()
          .where((l) => l.trim().startsWith('import '))
          .toList();
      expect(imports.where((l) => l.contains('secure_storage_adapter')),
          isEmpty,
          reason: '${f.path} must depend on SecretStore, not the adapter');
    }
  });
}
