// W4: PushPort — the compile-time seam for v1.1 push (BUILD-SPEC §1.3).
// v1 ships exactly one implementation: NoopPush. De-Googled builds are
// structurally push-free because nothing else exists to link against.
import 'dart:io';

import 'package:test/test.dart';

import 'package:porch_app/data/push_port.dart';

void main() {
  test('NoopPush subscribes to nothing and reports itself inactive', () async {
    const push = NoopPush();
    expect(push.isActive, isFalse);
    // Registering topics must be a no-op that never throws — callers may
    // hand it the (dormant) derived pushTopic unconditionally.
    await push.subscribe('sometopic');
    await push.unsubscribe('sometopic');
    expect(push.isActive, isFalse);
  });

  test('structurally: no FCM/APNs package is imported anywhere in lib/', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final line in f.readAsLinesSync()) {
        final t = line.trim();
        if (!t.startsWith('import ')) continue;
        if (t.contains('firebase') || t.contains('_messaging')) {
          offenders.add('${f.path}: $t');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'v1 is structurally push-free:\n${offenders.join('\n')}');
  });
}
