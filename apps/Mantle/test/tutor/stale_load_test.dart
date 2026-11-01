// test/tutor/stale_load_test.dart
//
// Try again on a screen controller starts a fresh load. A load begun by the
// earlier attempt, still waiting on the disk, must not write over the fresh
// one when it finally returns. On riverpod 3 a Notifier keeps its instance
// across a rebuild, so each load holds the ref of the build that started it
// and stops once that ref is unmounted.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/features/tutor/content/data/menswear_repository.dart';
import 'package:mantle/features/tutor/content/domain/menswear_term.dart';
import 'package:mantle/features/tutor/presentation/lean_round_controller.dart';

MenswearTerm _t(String id) => MenswearTerm(
    id: id, facet: 'garment', term: id, handle: null, gloss: '',
    quickRead: '', closerRead: '', axisSignals: const [], plateHint: '');

/// The first lean-pool read hangs until the test lets it go; later reads
/// answer at once.
class _SlowFirstRead extends MenswearRepository {
  final firstRead = Completer<List<MenswearTerm>>();
  int reads = 0;

  @override
  Future<List<MenswearTerm>> leanPool() {
    reads++;
    if (reads == 1) return firstRead.future;
    return Future.value(
        [for (final id in MenswearRepository.leanPoolIds) _t(id)]);
  }
}

void main() {
  test('a load from before Try again does not overwrite the fresh one',
      () async {
    final db = MantleDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = _SlowFirstRead();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      menswearRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final provider =
        leanRoundControllerProvider((memberId: 'm1', roundId: null));
    container.listen(provider, (_, __) {});
    expect(repo.reads, 1);

    // Try again while the first read still waits on the disk.
    container.invalidate(provider);
    container.read(provider);
    expect(repo.reads, 2);
    for (var i = 0;
        i < 100 && container.read(provider).phase != LeanRoundPhase.pairing;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(provider).phase, LeanRoundPhase.pairing);

    // The old read returns a pool too small for a round. Were it still
    // live, it would show "The lean pool is too small" over the round.
    repo.firstRead.complete(const []);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(provider).phase, LeanRoundPhase.pairing);
    expect(container.read(provider).errorMessage, isNull);
  });
}
