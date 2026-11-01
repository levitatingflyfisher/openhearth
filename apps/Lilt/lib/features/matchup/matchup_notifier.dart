import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lilt/core/providers/repository_providers.dart';
import 'package:lilt/core/providers/retry_policy.dart';
import 'package:lilt/core/providers/settings_providers.dart';
import 'package:lilt/domain/models/ranking.dart';

class MatchupState {
  /// The next two names to compare, or null when none are left.
  final NamePair? next;
  final bool isConverged;
  final int matchCount;
  final int estimatedTarget;

  /// Maps nameId to display name (e.g. "eliot-m" to "Eliot")
  final Map<String, String> idToDisplay;

  const MatchupState({
    this.next,
    required this.isConverged,
    required this.matchCount,
    required this.estimatedTarget,
    required this.idToDisplay,
  });

  /// Progress fraction 0.0-1.0. Caps at 0.95 until actually converged.
  double get progress {
    if (isConverged) return 1.0;
    if (estimatedTarget == 0) return 0.0;
    return (matchCount / estimatedTarget).clamp(0.0, 0.95);
  }

  /// True when user has done enough comparisons to get meaningful results.
  bool get canExitEarly => matchCount >= (estimatedTarget * 0.4).ceil();

  String get progressLabel {
    if (isConverged) return 'You’re done';
    return 'Match $matchCount of ~$estimatedTarget';
  }
}

class MatchupNotifier extends AsyncNotifier<MatchupState> {
  MatchupNotifier(this.sessionId);

  /// The family argument: riverpod 3 hands it to the constructor.
  final String sessionId;

  bool _recording = false;

  @override
  Future<MatchupState> build() => _loadState(sessionId);

  Future<MatchupState> _loadState(String sessionId) async {
    final sessionRepo = ref.read(sessionRepositoryProvider);
    final namesRepo = ref.read(namesRepositoryProvider);

    final session = await sessionRepo.getSession(sessionId);
    final tau = ref.read(convergenceTauProvider);
    final ranking =
        await sessionRepo.ranking(sessionId, convergenceTau: tau);
    final matchCount = await sessionRepo.getNonSkipMatchCount(sessionId);

    final poolIds = session?.poolIds ?? [];
    final names = await namesRepo.getByIds(poolIds);
    final idToDisplay = {for (final n in names) n.id: n.display};

    return MatchupState(
      next: ranking.next,
      isConverged: ranking.isConverged,
      matchCount: matchCount,
      estimatedTarget: _estimatedTarget(session?.poolSize ?? 60),
      idToDisplay: idToDisplay,
    );
  }

  Future<void> record(
      String idA, String idB, ComparisonOutcome outcome) async {
    if (_recording) return;
    _recording = true;
    try {
      final sessionRepo = ref.read(sessionRepositoryProvider);
      await sessionRepo.recordMatch(
        sessionId: sessionId,
        idA: idA,
        idB: idB,
        outcome: outcome,
      );
      state = AsyncData(await _loadState(sessionId));
    } finally {
      _recording = false;
    }
  }

  Future<void> undo() async {
    final sessionRepo = ref.read(sessionRepositoryProvider);
    await sessionRepo.undoLastMatch(sessionId);
    state = AsyncData(await _loadState(sessionId));
  }

  static int _estimatedTarget(int poolSize) => (poolSize * 1.6).ceil();
}

/// Not autoDispose, so it keeps what it read: it is in storedDataCaches
/// (lib/app/stored_data_caches.dart), which a restore and an erase reset.
final matchupProvider =
    AsyncNotifierProvider.family<MatchupNotifier, MatchupState, String>(
        MatchupNotifier.new,
        retry: noAutoRetry);
