# ADR-0005 — TTL-based ephemeral presence in Redis

**Status:** Accepted (built; see State today)

## Context

"Alice was available for a walk at 2:43pm on Tuesday" is exactly the kind of data that
should not accumulate. Presence is meaningful only *now*; a history of when everyone's light
was on is a behavioral dossier — sensitive, and a magnet for compromise. The porch-light
metaphor is emphatic about this: the light is on *right now* and no one keeps a log of when
it was on.

The naive approach — store presence rows in the durable database and mark them expired — is
wrong twice: expired-but-present data still exists to be subpoenaed or stolen, and it invites
someone, someday, to "just keep the history for analytics."

## Decision

Store presence as **ephemeral state in Redis under a TTL** equal to the availability window
(30 min / 1 hr / 2 hr / 4 hr). When the TTL lapses, Redis deletes the key — the data is
**structurally gone**, not soft-deleted. There is no presence table in Postgres; the durable
store holds only group/membership data (as ciphertext). The same TTL discipline already
governs the auth layer: challenges expire in 5 minutes, sessions in 30 days.

## Consequences

- **Positive:** expiry is enforced by the datastore, not by application code that could have
  a bug or be quietly changed. At compromise, presence is "noise, already expiring."
- **Positive:** it makes "we don't keep history" *checkable* — there is nowhere for history
  to live.
- **Positive:** cheap and fast; Redis is the right tool for high-churn, short-lived keys.
- **Negative:** no presence history means no server-side analytics on availability patterns
  — intentional; Porch measures success via a privacy-preserving proxy (same-day
  re-availability), not a presence log.
- **Negative:** Redis durability must be reasoned about (a flush loses in-flight presence) —
  acceptable, because presence is *meant* to be disposable; losing it just means lights read
  as off until the next tap.
- **State today (2026-09-28):** built. The relay writes each encrypted presence slot with
  a native store TTL, in memory or in Redis 7, capped at about 4 hours
  (`relay/internal/api/channels.go`; `maxPresenceTTL` in `router.go`), and the store
  conformance suite covers both (the Redis leg needs `REDIS_URL`). There is no Postgres and no durable presence row
  anywhere. The auth-layer TTLs this ADR cited (challenges, sessions) are gone with the
  session plane itself ([ADR-0006](0006-capability-channels-no-session-plane.md)); presence
  is polled over HTTPS, not pushed over a WebSocket.
