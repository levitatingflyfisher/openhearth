# ADR-0002 — A dumb end-to-end-encrypted relay, not a BaaS

**Status:** Accepted

## Context

Porch needs *some* server: to route an availability event from one device to the friends
who should see it, and to hold durable group/membership data. The fast path is a
backend-as-a-service — Firebase, Supabase, Auth0 — with realtime, auth, and a database out
of the box. The PRD listed "Supabase vs. a minimal custom server" as the single most
important pre-build decision.

The deciding factor is the **zero-logging guarantee**. Porch's entire value rests on the
server seeing as little as possible. A BaaS's logging, retention, and access posture are
*its* guarantees to make, not ours to assume — and it inserts a third party between friends,
holding exactly the metadata (who talks to whom, when) Porch is built to protect.

## Decision

Build a **minimal custom Go relay** and treat it as a **blind relay**, not a BaaS:

- It authenticates devices by public key (ed25519) and nothing else.
- It is designed to route only **end-to-end-encrypted** blobs; content is encrypted with a
  per-group key before it leaves the device.
- Durable data (group name, wrapped group keys) is stored as `BYTEA` **ciphertext** the
  server can't read; ephemeral presence lives in Redis under a TTL.
- It writes **zero access logs** and is open-source and self-hostable so the claims can be
  checked.

Go was chosen for a small, easy-to-deploy binary with a strong stdlib HTTP/WebSocket story
and full control over logging.

## Consequences

- **Positive:** logging, retention, and jurisdiction are Porch's own decisions, not a
  vendor's. `main.go`'s `silentHandler` and the PII-free schema (`001_init.sql`) make the
  posture checkable in a few files.
- **Positive:** self-hostable — a technical user can run their own relay and trust it
  completely.
- **Negative:** more to build and operate than a BaaS — the WebSocket presence router, the
  TTL presence store, and push fan-out are all ours to write (and, today, **unbuilt**).
- **Negative:** no free realtime/auth tier to lean on; scaling and reliability are our
  problem. Accepted, because for the target scale (small friend groups) the relay is cheap
  and simple, and the trust properties are the whole point.
- **State today:** the blind relay (`relay/`) and the client's end-to-end encryption
  (`app/lib/domain/`) are **built and tested on the host**. No relay is deployed. The
  details above describe the first relay, which was deleted
  ([ADR-0007](0007-ground-up-competition.md)): today there is no public-key login, no
  Postgres schema, no `silentHandler`, no WebSocket router and no push.
  [ADR-0006](0006-capability-channels-no-session-plane.md) replaced how the relay is
  reached, and presence is polled over HTTPS. See [security-model](../security-model.md)
  and [feature-status](../reference/feature-status.md).
