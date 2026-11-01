# ADR-0006 — Capability channels, and no session plane

**Status:** Accepted (supersedes the routing half of [ADR-0002](0002-dumb-e2e-relay-not-baas.md) and the session model implied by [ADR-0003](0003-ed25519-identity-no-accounts.md))

## Context

The pre-v1 relay authenticated every request with an ed25519 challenge/response
handshake and issued 30-day session tokens (`server/internal/auth`). That spine
was real and tested — but a session plane binds a public key to an IP-bearing
session for weeks, and during rotation fan-out a live-compromised server sees
sender-identity → recipient-mailbox edges: exactly the social graph the threat
model ([ADR-0002](0002-dumb-e2e-relay-not-baas.md)) promises the server cannot
learn. A ground-up design competition (three independent architectures scored by
a three-judge panel — see [docs/explanation/build-spec.md](../explanation/build-spec.md))
converged on removing the session plane entirely.

## Decision

Route by **capabilities derived from keys the server never holds.** Each group
has a 256-bit symmetric key with an epoch counter; the wire address
(`channelId`) and per-member presence slots are **KDF-derived from that key.**
Two consequences fall out:

- **Rotation revokes routing and decryption in one act.** A removed member's old
  key no longer decrypts *and* no longer addresses the new channel — the server
  cooperates in neither and learns of neither.
- **There is no session plane.** No challenge endpoint, no tokens, no 30-day
  server-side session state, no pubkey↔IP binding. The two request planes are:
  - **Channel plane** (`/v1/ch/*`) — addressed by the capability, authenticated
    only by *knowledge* of it; the client structurally forbids identity headers
    on these paths (grep-tested).
  - **Mailbox plane** (`/v1/mailbox/*`) — POST is **anonymous** (rate-limited,
    size/depth-capped); drain is a **stateless ed25519-signed request**
    (`porch-drain|{mailboxId}|{ts}`, ±300 s freshness, replay cache). No stored
    session.

At full compromise the server holds anonymous key hashes and opaque
TTL-expiring ciphertext keyed by random-looking capabilities, with no stored
link between them.

## Consequences

- **Positive:** the compromise table is satisfied *structurally*; the API is
  smaller (no auth/session subsystem); rotation is the single lever for both
  secrecy and reachability.
- **Positive:** presence changes on a minutes-to-hours scale, so v1 is **HTTPS
  polling only** (25 s while the feed is visible) — the WebSocket hub and its
  per-connection correlation surface are deleted too.
- **Negative / residual:** the drain signature still presents the caller's
  ed25519 public key to the relay in cleartext (needed to verify the signature),
  so the relay *could* correlate drains by key over time. Presence and social
  graph stay protected; this timing/identity-on-drain channel is a named
  residual in [HONEST-STATUS](../../HONEST-STATUS.md) and the threat model, not
  a silent gap.
- **Cost:** the tested session auth spine was retired, not reused — a real
  deletion of working code, justified by the privacy gain.
