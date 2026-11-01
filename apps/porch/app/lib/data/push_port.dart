// push_port — the PushPort seam (BUILD-SPEC §1.3, §2 module map).
//
// v1 ships NO push transport: NoopPush is the ONLY implementation, chosen at
// compile time, so de-Googled/GrapheneOS builds are structurally push-free
// (nothing FCM-shaped exists to link — a test greps for that). The keyring
// already derives a dormant pushTopic per epoch, so the v1.1 FCM adapter
// needs no protocol change: it will implement this same interface.
abstract interface class PushPort {
  /// Whether a real push transport is wired. Renderers may use this to
  /// explain notification latency honestly ("Porch checks in the
  /// background; nothing pushes to your phone").
  bool get isActive;

  /// Subscribe to a (dormant, key-derived) topic. No-op in v1.
  Future<void> subscribe(String topic);

  /// Unsubscribe. No-op in v1.
  Future<void> unsubscribe(String topic);
}

/// The only v1 implementation: does nothing, links nothing, leaks nothing.
class NoopPush implements PushPort {
  const NoopPush();

  @override
  bool get isActive => false;

  @override
  Future<void> subscribe(String topic) async {}

  @override
  Future<void> unsubscribe(String topic) async {}
}
