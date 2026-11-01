# ADR-0007 — The v1 client and relay came from a blind ground-up competition

**Status:** Accepted (records how the current `app/` and `relay/` were produced)

## Context

At the end of the scaffold era, Porch had a tested server auth spine and a
counter-template Flutter app — the client, the crypto, and the presence relay
were all "designed, not built" ([feature-status](../reference/feature-status.md)).
Rather than grow the skeleton, we ran a **blind ground-up competition**: build
Porch again from the PRD alone and compare.

## Decision

Three independent architectures were designed **from the PRD only** (agents
barred from reading this repo), on three different angles — ruthless-YAGNI
("One Lamp, One Wire"), crypto-first ("Capability Channels"), and product-first
("Porch"). A three-judge panel (PRD-fidelity, crypto-security, maintainer
lenses) scored them on prd-fit / crypto-soundness / simplicity / testability /
house-fit. **Capability Channels won (252 vs 248 vs 247)** — close, so the
winner was implemented with **20 grafts** from the runners-up folded in
(notably: the anonymous-mailbox + stateless-drain that deletes the session
plane; the typed `PresenceSnapshot(fetchedAt:)` honesty invariant; on-device
success metrics; the privacy-conformance test; the widget long-press toggle
path; the 12-word mnemonic; the "void — regenerate" invite fallback).

The winning design was then built TDD-first across five work packages (relay,
domain, data, presentation, finisher) and adversarially verified. The result —
382+ tests green, race-clean relay, byte-identity privacy conformance — replaced
`server/` and the app skeleton wholesale.

## What was kept from the pre-competition work

- The **design intent**: [ADR-0001](0001-presence-not-communication.md) (presence
  not communication), [ADR-0002](0002-dumb-e2e-relay-not-baas.md) (blind relay),
  [ADR-0005](0005-ttl-ephemeral-presence.md) (TTL presence) all still hold; the
  competition strengthened them ([ADR-0006](0006-capability-channels-no-session-plane.md)).
- The **passkey spike finding** ([ADR-0004](0004-seed-backup-recovery-over-passkeys.md)):
  seed-first recovery, passkey demoted — the blind build independently chose the
  same, because the same Flutter tooling constraint still holds.
- The **homescreen-widget spikes** (iOS WidgetKit + Android AppWidget), grafted
  onto the new client.

## What was retired

- `server/` (the ed25519 session auth spine) — deleted, not ported; the winning
  architecture has no session plane ([ADR-0006](0006-capability-channels-no-session-plane.md)).
- The counter-template `app/lib/main.dart`.

## Consequences

- **Positive:** the client is real and tested end-to-end against a
  behaviorally-twinned relay, not a spike.
- **Honest residual:** the app has **never run on a device** — all platform glue
  (secure storage, `sodium_libs` binaries, `path_provider`, the widget bridge)
  is untested on hardware. First sideload is first run. Tracked in
  [HONEST-STATUS](../../HONEST-STATUS.md).
- **Method note:** competing implementations is expensive (≈2M tokens here). It
  earns its cost when the design space is genuinely open and correctness matters
  more than speed — which is exactly the case for a privacy-critical crypto app.
