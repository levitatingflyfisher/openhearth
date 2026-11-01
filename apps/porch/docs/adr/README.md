# Architecture Decision Records

Load-bearing decisions, in the lightweight [Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
format (Status · Context · Decision · Consequences). These capture the choices a future
maintainer might otherwise re-litigate. Because Porch is pre-release, several ADRs record a
decision that is *made* but whose implementation is still ahead — the ADR is where the
rationale lives so it isn't lost between now and then.

| # | Decision | Status |
|---|---|---|
| [0001](0001-presence-not-communication.md) | Presence signal, not a communication channel | Accepted |
| [0002](0002-dumb-e2e-relay-not-baas.md) | A dumb end-to-end-encrypted relay, not a BaaS | Accepted; routing half superseded by 0006 |
| [0003](0003-ed25519-identity-no-accounts.md) | ed25519 keypair identity — no accounts, no PII | Accepted (built); its session model superseded by 0006 |
| [0004](0004-seed-backup-recovery-over-passkeys.md) | Seed backup is primary recovery; passkey is local-unlock only | Accepted (spike-driven) |
| [0005](0005-ttl-ephemeral-presence.md) | TTL-based ephemeral presence in Redis | Accepted (built: memory or Redis store) |
| [0006](0006-capability-channels-no-session-plane.md) | Capability channels, and no session plane | Accepted (built) |
| [0007](0007-ground-up-competition.md) | The v1 client and relay came from a blind ground-up competition | Accepted (records how `app/` and `relay/` were produced) |
