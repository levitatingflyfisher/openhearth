import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/audio/audio.dart';
import '../providers/core_providers.dart';
import '../providers/retry_policy.dart';
import 'engine_service.dart';

part 'engine_providers.g.dart';

/// One engine per profile, loaded from its snapshot. keepAlive so switching
/// screens mid-session doesn't reload the engine; profile switch changes the
/// family argument and naturally builds a fresh one. A failed load is not
/// retried on its own: the Nursery shows its refresh button instead.
@Riverpod(keepAlive: true, retry: noAutoRetry)
Future<EngineService> engineService(Ref ref, int profileId) async {
  final service = EngineService(ref.watch(appDatabaseProvider), profileId);
  await service.load();
  ref.onDispose(service.dispose);
  return service;
}

/// The one AudioService. The mute flag is *listened* to, never read on demand:
/// soundMuted is an auto-dispose stream provider, and a bare `ref.read` from
/// here neither subscribes nor keeps it alive, so every cue rebuilt it, found
/// it still `AsyncLoading`, and fell through to the safe default — muted. The
/// app shipped completely silent and nothing failed, because silence is what
/// a broken audio path is supposed to look like. A subscription lives as long
/// as this (keepAlive) provider, so the flag lands once and stays.
///
/// Cold start still starts silent: until the database answers, a child who
/// muted the app must not be blasted on the next launch.
///
/// The subscription is the container's, not this provider's. Riverpod 3
/// pauses a provider's own `ref.listen` whenever nothing listens to that
/// provider, and the app mostly *reads* this one (main, Rush), so a
/// `ref.listen` here went quiet before the flag landed: silent again. A
/// container subscription is never paused; it is closed with the service.
@Riverpod(keepAlive: true)
AudioService audioService(Ref ref) {
  var muted = true;
  final mutedSub = ref.container.listen(soundMutedProvider, (_, next) {
    final value = next.value;
    if (value != null) muted = value;
  }, fireImmediately: true);
  ref.onDispose(mutedSub.close);
  final service = AudioService(isMuted: () => muted);
  service.preload();
  ref.onDispose(service.dispose);
  return service;
}
