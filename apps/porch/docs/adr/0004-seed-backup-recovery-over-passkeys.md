# ADR-0004 — Seed backup is primary recovery; passkey is local-unlock only

**Status:** Accepted (spike-driven)

## Context

With identity as a device-held keypair and no accounts ([ADR-0003](0003-ed25519-identity-no-accounts.md)),
**recovery** is the hard problem: how do you get your identity back on a new device without
the server ever holding something that could recover it *for* you (which would break the
threat model)?

The original design leaned on **passkeys (FIDO2)** as the primary recovery path — using the
passkey's PRF (`hmac-secret`) extension to derive a Key Encryption Key that wraps the
ed25519 private key, so a passkey in the user's authenticator (iCloud Keychain, Bitwarden,
1Password, KeePassXC) could unwrap the key on a new device.

A spike (see [PASSKEY_SPIKE.md](../PASSKEY_SPIKE.md)) tested this against the actual Flutter
package. **Finding: the `passkeys` package (v2.18.0) does not expose the PRF extension** —
`clientExtensionResults` is hardcoded to an empty map in both register and authenticate
responses, so no KEK can be derived. The PRF-based recovery architecture is **not
implementable** with the available tooling.

## Decision

Restructure recovery so that a **PIN-encrypted seed backup is the primary path**, and the
passkey is demoted to a **local-unlock convenience only**:

- The ed25519 keypair lives in the OS keychain/keystore (`flutter_secure_storage`).
- **Backup:** `Argon2(PIN, salt)` → KEK → `secretbox(ed25519_sk)` → a file the user stores
  in their own cloud/documents. **The server never sees it.**
- **Recovery on a new device:** install → enter PIN → Argon2 → decrypt the seed → restore
  the key → log in. No server-side recovery exists, by design.
- **Passkey** (where the platform supports it) proves device possession to gate local app
  unlock — it is *not* used for key recovery.

Because the seed is the only cross-device recovery path, onboarding must **strongly
encourage** the backup (not bury it as optional) and warn plainly that skipping it means a
lost device = a permanently lost identity.

## Consequences

- **Positive:** recovery stays entirely client-side; the threat model is preserved (the
  server cannot recover a user's key even under compromise).
- **Positive:** works everywhere, including de-Googled Android where passkey/FIDO2 support
  is weakest — the seed phrase is exactly the right primitive for that user.
- **Negative:** more user responsibility. A forgotten PIN or a lost seed file is
  unrecoverable. The UX must make the backup feel important without being a nag.
- **Negative:** the passkey's role shrank from "recovery" to "unlock UX," so its value is
  smaller than originally planned — acceptable, since the seed carries recovery.
- **State today:** the seed-first path is **built and tested on the host**: the 12
  recovery words, the backup file (Argon2id, then XChaCha20-Poly1305, in
  `app/lib/domain/identity.dart`) and restore from either on a new phone's first screen.
  None of it has run on a device. The passkey unlock is not built. The relay has no
  login ([ADR-0006](0006-capability-channels-no-session-plane.md)), so the "log in" step
  above no longer exists.
- **Amended, November 2026:** the backup is no longer locked by a PIN the person picks.
  A 4-digit PIN fell to hours of guessing on one core, and the file is made to travel.
  It is locked by 6 backup words (66 bits) that Porch derives from the identity and
  shows beside the 12 words, and it is kept out of automatic backups.
