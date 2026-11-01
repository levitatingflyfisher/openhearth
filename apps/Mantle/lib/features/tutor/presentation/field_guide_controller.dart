import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../ranking/data/matches_dao.dart';
import '../../ranking/data/sessions_dao.dart';
import '../../solo/data/read_progress_dao.dart';
import '../content/data/menswear_repository.dart';
import '../content/domain/archetype.dart';
import '../content/domain/menswear_term.dart';
import '../domain/axis_tally.dart';

enum FieldGuideStatus { loading, ready, error }

class FieldGuideState {
  const FieldGuideState({
    this.status = FieldGuideStatus.loading,
    this.position = const AxisPosition({}),
    this.pickCount = 0,
    this.match,
    this.hasEnoughSignal = false,
    this.lexicon = const [],
    this.archetypes = const [],
    this.errorMessage,
  });

  final FieldGuideStatus status;
  final AxisPosition position;
  final int pickCount;

  /// Nearest archetype — null until [hasEnoughSignal] is true.
  final ArchetypeMatch? match;
  final bool hasEnoughSignal;
  final List<MenswearTerm> lexicon;

  /// All archetypes (for adjacency lookup in the UI).
  final List<Archetype> archetypes;
  final String? errorMessage;
}

final fieldGuideControllerProvider = NotifierProvider.autoDispose
    .family<FieldGuideController, FieldGuideState, String>(
  FieldGuideController.new,
);

/// Assembles the solo Field Guide from a member's accumulated menswear picks
/// (→ axis position → nearest archetype) and their lexicon (`ReadProgress`).
class FieldGuideController extends Notifier<FieldGuideState> {
  FieldGuideController(this.memberId);

  final String memberId;
  late SessionsDao _sessionsDao;
  late MatchesDao _matchesDao;
  late ReadProgressDao _readProgressDao;
  late MenswearRepository _repo;

  @override
  FieldGuideState build() {
    _sessionsDao = ref.watch(sessionsDaoProvider);
    _matchesDao = ref.watch(matchesDaoProvider);
    _readProgressDao = ref.watch(readProgressDaoProvider);
    _repo = ref.watch(menswearRepositoryProvider);
    unawaited(_init());
    return const FieldGuideState();
  }

  Future<void> _init() async {
    // This build's ref. A rebuild or dispose unmounts it, so work begun by an
    // older build stops instead of writing over the new state.
    final ref = this.ref;
    try {
      final terms = await _repo.terms();
      final archetypes = await _repo.archetypes();
      if (!ref.mounted) return;
      final byId = {for (final t in terms) t.id: t};

      final sessions =
          await _sessionsDao.forMemberInDomain(memberId, kMenswearDomainKey);
      final matchesBySession =
          await _matchesDao.forRound(sessions.map((s) => s.id).toList());
      if (!ref.mounted) return;

      final chosen = <MenswearTerm>[];
      for (final s in sessions) {
        for (final m in matchesBySession[s.id] ?? const []) {
          final winnerId = m.outcome == 'aWins' ? m.idA : m.idB;
          final t = byId[winnerId];
          if (t != null) chosen.add(t);
        }
      }

      final pickCount = chosen.length;
      final position = AxisTally.positionFromChoices(chosen);
      final enough = AxisTally.hasEnoughSignal(pickCount);
      final match = enough && archetypes.isNotEmpty
          ? AxisTally.nearestArchetype(position, archetypes)
          : null;

      final progress = await _readProgressDao.progressForMember(memberId);
      if (!ref.mounted) return;
      final learnedIds = progress.map((p) => p.itemId).toSet();
      final lexicon = terms.where((t) => learnedIds.contains(t.id)).toList();

      state = FieldGuideState(
        status: FieldGuideStatus.ready,
        position: position,
        pickCount: pickCount,
        match: match,
        hasEnoughSignal: enough,
        lexicon: lexicon,
        archetypes: archetypes,
      );
    } catch (e, st) {
      debugPrint('Field Guide failed: $e\n$st');
      if (!ref.mounted) return;
      state = const FieldGuideState(
        status: FieldGuideStatus.error,
        errorMessage: 'We couldn’t assemble your Field Guide.',
      );
    }
  }
}
