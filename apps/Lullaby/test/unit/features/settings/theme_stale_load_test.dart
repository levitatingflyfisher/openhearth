// The theme loads after the first frame when main() could not read it in
// time. Riverpod 3 keeps the same Notifier object across a rebuild, so a load
// started by an earlier build must not write over what the newer build read.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/features/settings/presentation/controllers/theme_controller.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

/// Answers each read from [answers], in order.
class _QueuedStorage implements SecretStorage {
  _QueuedStorage(this.answers);
  final List<Future<String?> Function()> answers;
  var reads = 0;

  @override
  Future<String?> read(String key) {
    final i = reads < answers.length ? reads : answers.length - 1;
    reads++;
    return answers[i]();
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

void main() {
  test('a load from before a rebuild never writes over the newer one',
      () async {
    final slow = Completer<String?>();
    final storage = _QueuedStorage([
      () => slow.future,
      () async => null,
    ]);
    final c = ProviderContainer(overrides: [
      themeStorageProvider.overrideWithValue(storage),
    ]);
    addTearDown(c.dispose);
    c.listen(themeModeProvider, (_, _) {});
    await pumpEventQueue();
    expect(storage.reads, 1);

    c.invalidate(themeModeProvider);
    c.read(themeModeProvider);
    await pumpEventQueue();
    expect(storage.reads, 2);
    expect(c.read(themeModeProvider), OhThemeModePreference.system);

    slow.complete('dark');
    await pumpEventQueue();

    expect(c.read(themeModeProvider), OhThemeModePreference.system,
        reason: 'the newer build read nothing stored; the old read is stale');
  });
}
