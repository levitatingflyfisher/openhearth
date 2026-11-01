# Reference: relay API

The HTTP surface of `relayd` as it exists in `relay/internal/api/` (routes in
`router.go`). This page is written from that code; when they disagree, the code wins.
The relay is **blind**: every `blob` is ciphertext the client produced, stored and
returned byte-for-byte, never parsed.

> The pre-rebuild relay had `/auth/*` endpoints, sessions, Postgres tables and a
> `server/` directory. All of that was removed by
> [ADR-0006](../adr/0006-capability-channels-no-session-plane.md); none of it exists now.

## Conventions

- JSON bodies. Binary fields (`blob`, `pubkey`, `sig`) are **standard base64** strings
  (Go's `[]byte` JSON encoding). Unknown JSON fields are rejected with `400`.
- Identifiers (`{id}`, `inviteId`, `slotId`) are 16–64 characters of the base64url
  alphabet `A–Z a–z 0–9 - _`; `proof` is 16–128 of the same. A malformed path id is `404`.
- Errors are bare status codes with **no body**. Common ones: `400` bad input, `404`
  unknown / expired / wrong proof, `410` invite already used, `409` invite id already exists, `413` blob
  over its cap, `429` rate-limited or a store cap reached, `507` the store is full (Redis at
  its memory ceiling refuses writes by design; try again later), `500` anything else.
- No request is logged, anywhere (a grep test gates the package).
- Every route except `healthz` sits behind a per-IP token bucket (IP used for limiting
  only, never stored). With `-trust-forwarded`, the IP is the last `X-Forwarded-For` hop.

## Endpoints

| Method + path | Body in | 2xx out | Notes |
|---|---|---|---|
| `GET /v1/healthz` | — | `200` | liveness only |
| `POST /v1/invites` | `{inviteId, ttlHours}` | `201 {expiresAt}` | `ttlHours` 1–72; `expiresAt` is Unix seconds |
| `POST /v1/invites/{id}/join` | `{blob}` | `204` | invitee's join intro, ≤ 8 KiB; one use (`410` after) |
| `GET /v1/invites/{id}/join?proof=` | — | `200 {blob}` | inviter fetches the intro |
| `POST /v1/invites/{id}/grant` | `{proof, blob}` | `204` | inviter's grant bundle, ≤ 16 KiB |
| `GET /v1/invites/{id}/grant?proof=` | — | `200 {blob}` | invitee takes the grant; **deleted on retrieval** |
| `POST /v1/mailbox/{id}` | `{blob}` | `204` | anonymous post to a mailbox, ≤ 8 KiB; `429` when full, or when it would open a never-drained mailbox past the relay's cap |
| `POST /v1/mailbox/{id}/drain` | `{pubkey, ts, sig}` | `200 {blobs: [...]}` | signed drain; returned blobs are deleted atomically |
| `POST /v1/ch/{id}/presence` | `{slotId, blob, ttlSec}` | `204` | presence envelope ≤ 1 KiB; `ttlSec` 1–14700; the slot expires on its own |
| `GET /v1/ch/{id}/presence` | — | `200 {slots: [{slotId, blob, expiresAt}]}` | live slots only, sorted by `slotId` |
| `POST /v1/ch/{id}/bulletin` | `{slotId?, blob, pinned, ttlSec}` | `200 {seq}` | ≤ 8 KiB; `slotId` is an opaque writer id (16–64 characters) when sent: the app derives a per-epoch bulletin writer id, unlike its presence slot id; pinned needs `ttlSec` 1–259200, unpinned needs `ttlSec` 0; `429` at the pin cap, or when it would open a channel past the relay's cap |
| `GET /v1/ch/{id}/bulletin?afterSeq=` | — | `200 {entries: [{seq, blob, pinned, expiresAt?}]}` | `expiresAt` only on pinned entries |

### The mailbox drain signature

The only request that proves identity. `sigauth.go`:

- The mailbox id must equal `base64url_nopad(BLAKE2b-256("porch/mbox/v1" ‖ pubkey))`.
- `ts` must be within 300 s of the relay's clock.
- `sig` is Ed25519 over the ASCII string `porch-drain|<mailboxId>|<ts>`.
- Each signature is accepted once: its SHA-256 goes into a replay cache for 10 minutes.

Any failure is a bare `401`.

## Storage

`relay/internal/store/store.go` defines one `Store` interface with two implementations:
`memstore.go` (in-process, the default `-store=memory`) and `redisstore.go`
(`-store=redis`). Both pass the same conformance suite (`conformance_test.go`; the Redis
leg runs only when `REDIS_URL` is set). Default limits (`DefaultLimits`):

| Limit | Value |
|---|---|
| Mailbox depth | 200 blobs |
| Mailbox TTL | 30 days, refreshed on each post, once the owner has drained the mailbox (a drain marks it owned for 30 days) |
| Never-drained mailbox TTL | 72 hours, refreshed on each post |
| Never-drained mailboxes, relay-wide | 20,000 at once; a mailbox its owner drains is never refused |
| Channels (bulletin or presence), relay-wide | 20,000 at once; a channel holds its place 72 hours at most (refreshed on each write) until a second id writes to it (a presence slot, or a writer named by a bulletin write), then for its full life. The ring keeps its own 60-day TTL either way |
| Openings per address | 50 a day (`-opens-per-day`): a new mailbox, a new channel, or a mailbox's first drain by its owner each count one. At most 50 at once, then one more every 29 minutes. Past it, a write that would open something is `429`; writes to what exists are never counted, and a drain still returns the mail but does not make the mailbox owned |
| Bulletin ring | the last 8 unpinned entries; 60-day TTL, refreshed on each append |
| Pinned bulletin entries per channel | 16 |

Rate limits are per client address, and an IPv6 address counts by its /64. In the compose
file Redis is capped at 512 MB with `noeviction`: when full it refuses writes by design,
and the relay answers `507` until keys expire. It never drops a key to make room. The
caps bound counts, not bytes, so a relay under attack is expected to fill.

There are no tables, no accounts and no user records. Presence exists only as TTL'd
slots and is structurally gone after expiry
([ADR-0005](../adr/0005-ttl-ephemeral-presence.md)).
