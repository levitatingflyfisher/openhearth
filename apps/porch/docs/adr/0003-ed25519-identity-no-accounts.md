# ADR-0003 — ed25519 keypair identity — no accounts, no PII

**Status:** Accepted (built)

## Context

Every app needs to know *which device* it's talking to. The default answer is an account:
email or phone, a password or an OAuth provider. But an account is precisely the PII Porch
promises never to collect — and an email/phone identifier is a durable handle that ties a
person's presence data to their real identity forever. For a tool whose threat model
includes full server compromise, storing any identifier that names a person is a liability.

## Decision

Identity is a **locally generated ed25519 keypair**. There are no accounts, no email, no
phone number, no Google/Apple sign-in.

- **Registration is trust-on-first-use:** the app sends its **public key**; the relay
  stores it (`users.public_key BYTEA UNIQUE`) and issues a session token. No identity is
  proven at registration because there is nothing to prove.
- **Login proves key possession:** the relay issues a random 32-byte challenge (5-min Redis
  TTL); the device signs it; the relay verifies with `ed25519.Verify`. Challenges are
  single-use (`GetDel`).
- **Sessions** are opaque random tokens in Redis (30-day TTL), checked by
  `middleware.RequireAuth`.
- **The private key never leaves the device.**

This was real when this record was written: `server/internal/auth/service.go`,
`handler.go`, and a Postgres/Redis-gated test suite (`service_test.go`) covering register,
login, invalid-signature, expired-challenge, and invalid-key-size.

**State today:** the keypair identity stands and is built (`app/lib/domain/identity.dart`).
The registration, login and session bullets above describe the first relay. That relay
and its `server/` folder were deleted in the ground-up rebuild
([ADR-0007](0007-ground-up-competition.md)), and
[ADR-0006](0006-capability-channels-no-session-plane.md) removed the session plane. The
relay in `relay/` has no login, stores no public key, and sees one only when a device
drains its own mailbox.

## Consequences

- **Positive:** the server literally cannot name a user. At full compromise the identity
  column yields an anonymous key. **COPPA compliance becomes structural** — a good-faith
  age gate suffices because no PII is collected from anyone.
- **Positive:** no password reset flow, no account-takeover-by-email attack surface, no
  third-party identity provider.
- **Negative — recovery is hard.** No account means no server-side "reset." Losing the
  device *and* the key backup means losing the identity permanently. Porch's answer is a
  PIN-encrypted seed backup — see [ADR-0004](0004-seed-backup-recovery-over-passkeys.md).
- **Negative — multi-device is non-trivial.** One keypair maps naturally to one device;
  simultaneous devices need a linked-device key exchange. Deferred, but the key-storage
  model should leave room for a per-user device list (see [limitations](../limitations.md)).
