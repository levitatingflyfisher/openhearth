// PorchEnv — the data layer's dependency bundle. One place where the four
// capabilities every repository needs (crypto, relay, storage, identity)
// plus the injectable clock come together; presentation (W4) builds exactly
// one of these at bootstrap.
import 'package:sodium/sodium.dart' show Sodium;

import '../domain/domain.dart' show PorchIdentity;
import 'relay_api.dart';
import 'state_store.dart';

/// §1.6/§3.6: maximum random delay for rotation mailbox fan-out posts.
/// N near-simultaneous anonymous POSTs would let a live-compromised relay
/// infer probabilistic co-membership; each bundle is spread over [0, this].
const rotationFanoutJitterMaxSec = 30;

class PorchEnv {
  final Sodium sodium;
  final RelayApi relay;
  final StateStore stateStore;
  final PorchIdentity identity;

  /// Unix seconds. Injectable so every time-dependent behavior is testable.
  final int Function() now;

  /// Per-post rotation fan-out delay in seconds. Injectable so tests can
  /// script the schedule; null (production) draws real randomness from
  /// libsodium in [0, rotationFanoutJitterMaxSec].
  final int Function()? rotationJitter;

  const PorchEnv({
    required this.sodium,
    required this.relay,
    required this.stateStore,
    required this.identity,
    required this.now,
    this.rotationJitter,
  });

  int nextRotationJitterSec() {
    final custom = rotationJitter;
    if (custom != null) return custom();
    return sodium.randombytes.uniform(rotationFanoutJitterMaxSec + 1);
  }
}
