import 'dart:async';

import 'package:elo_engine/elo_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../ranking/data/matches_dao.dart';
import '../../ranking/data/sessions_dao.dart';
import '../../ranking/domain/session_builder.dart';
import '../../reveal/domain/reveal.dart';
import '../../reveal/domain/reveal_service.dart';
import '../content/data/menswear_repository.dart';
import '../content/domain/menswear_term.dart';
import '../domain/axis_tally.dart';

enum MenswearCharterStatus { loading, ready, error }

class MenswearCharterState {
  const MenswearCharterState({
    this.status = MenswearCharterStatus.loading,
    this.spine = const [],
    this.contested = const [],
    this.spineIsFallback = false,
    this.throughlinePoles = const [],
    this.termsById = const {},
    this.errorMessage,
  });

  final MenswearCharterStatus status;
  final List<RevealItem> spine;
  final List<RevealItem> contested;
  final bool spineIsFallback;
  final List<AxisPole> throughlinePoles;
  final Map<String, MenswearTerm> termsById;
  final String? errorMessage;
}

final menswearCharterControllerProvider = NotifierProvider.autoDispose
    .family<MenswearCharterController, MenswearCharterState, String>(
  MenswearCharterController.new,
);

/// Builds the family menswear Charter: both members' lean picks over one
/// `'menswear'` bucket → the generalized `RevealService` (Spine/Contested) →
/// through-lines via `AxisTally` on the merged choices.
class MenswearCharterController extends Notifier<MenswearCharterState> {
  MenswearCharterController(this.roundId);

  final String roundId;
  late SessionsDao _sessionsDao;
  late MatchesDao _matchesDao;
  late MenswearRepository _repo;

  @override
  MenswearCharterState build() {
    _sessionsDao = ref.watch(sessionsDaoProvider);
    _matchesDao = ref.watch(matchesDaoProvider);
    _repo = ref.watch(menswearRepositoryProvider);
    unawaited(_init());
    return const MenswearCharterState();
  }

  Future<void> _init() async {
    // This build's ref. A rebuild or dispose unmounts it, so work begun by an
    // older build stops instead of writing over the new state.
    final ref = this.ref;
    try {
      final pool = await _repo.leanPool();
      final terms = await _repo.terms();
      if (!ref.mounted) return;
      final itemIds = pool.map((t) => t.id).toList();
      final byId = {for (final t in terms) t.id: t};

      final sessions = await _sessionsDao.forRound(roundId);
      final menswearSessions =
          sessions.where((s) => s.domain == kMenswearDomainKey).toList();
      final matchesBySession = await _matchesDao
          .forRound(menswearSessions.map((s) => s.id).toList());
      if (!ref.mounted) return;

      final eloSessions = <EloSession>[];
      final allChosen = <MenswearTerm>[];
      for (final s in menswearSessions) {
        final rows = matchesBySession[s.id] ?? const [];
        eloSessions.add(SessionBuilder.buildSession(
          itemIds: itemIds,
          matches: rows,
          sessionId: s.id,
          participantId: s.memberId,
        ));
        for (final m in rows) {
          final winnerId = m.outcome == 'aWins' ? m.idA : m.idB;
          final t = byId[winnerId];
          if (t != null) allChosen.add(t);
        }
      }

      // Single 'menswear' bucket — one facet-agnostic Spine over the pool.
      final reveal =
          RevealService.compute({kMenswearDomainKey: eloSessions});
      final poles = AxisTally.throughlinePoles(
          AxisTally.positionFromChoices(allChosen));

      if (!ref.mounted) return;
      state = MenswearCharterState(
        status: MenswearCharterStatus.ready,
        spine: reveal.spine,
        contested: reveal.contested,
        spineIsFallback: reveal.spineIsFallback,
        throughlinePoles: poles,
        termsById: byId,
      );
    } catch (e, st) {
      debugPrint('Menswear charter failed: $e\n$st');
      if (!ref.mounted) return;
      state = const MenswearCharterState(
        status: MenswearCharterStatus.error,
        errorMessage: 'We couldn’t assemble your Wardrobe Charter.',
      );
    }
  }
}
