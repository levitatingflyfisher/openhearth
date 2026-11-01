// Porch domain layer — pure Dart, no Flutter, no IO, no network.
// (BUILD-SPEC W2: entities, identity/keys, group-key lifecycle, invite
// handshake, presence encode/encrypt/decode, admin succession.)
//
// Everything here is a pure function or an immutable value over libsodium
// primitives; the data layer (W4) owns storage and HTTP and calls in.
library;

export 'envelope.dart';
export 'identity.dart';
export 'invite.dart';
export 'keyring.dart';
export 'mnemonic.dart';
export 'presence.dart';
export 'roster.dart';
export 'rotation.dart';
export 'support/bytes.dart';
export 'support/canonical_json.dart';
