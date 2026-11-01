# Vision

> The north star for `sanctuary_auth_core`. If you (person or agent) are about to
> change something load-bearing, read this first. It says what must stay true and
> why. For how to work in the repo and where each file is, see
> [AGENTS.md](AGENTS.md). For the API and the known sync defect, see the
> [README](README.md).

## The one idea

**A household's identity is twelve words that the household holds.**

Every key an app needs is derived from those words, on the device. An app can
encrypt, back up and restore without an account and without a server.

## What this is

A Flutter library shared by the OpenHearth apps, which are free, local-first
tools for households. An app depends on it by path and gets:

```
  twelve words             one 64-byte seed            five 32-byte keys
 ----------------        -------------------        ----------------------
  BIP39, English    -->   PBKDF2-HMAC-SHA512   -->   HKDF-SHA256, one label
  made on device          (the BIP39 rule)           per purpose
                                                            |
                                                            v
                                             ChaCha20-Poly1305 envelope,
                                             written as an OHBK backup blob
```

- **The words.** Generate, validate and turn a 12-word BIP39 phrase into a seed.
- **The keys.** Five keys from one seed, each for one purpose. An app may pass
  its own `appDomain`, and then its keys differ from every other app's keys
  under the same words.
- **The envelope.** Authenticated encryption, and the OHBK blob format that
  carries a backup.
- **The key store.** A wrapper over the platform's secure storage that keeps
  the phrase.
- **The state.** A Riverpod notifier that an app watches: is there a phrase,
  has the user proved they wrote it down, when was the last backup.
- **An older sync layer.** A relay client, a three-way merge and an
  orchestrator under `lib/src/sync/`. It has a known defect and is marked for
  removal. See the scorecard.

The apps that use it are the Flutter apps of the fleet. Comments in the code
name three callers: Lullaby (the legacy derivation with no `appDomain`),
Sundial (an `appDomain` example) and StillLife (`KeyDerivation.deriveKey` for
its LAN pairing code). Those are comments. Check the app before you rely on
them.

This library has no screens. Backup and restore screens live in a sibling
package.

## The invariants (do not break these)

Each line below is held today by the file or test named after it. A change
that breaks one makes existing backups unreadable, or removes a protection.

1. **The Ghost tier needs no network and no account.** The only file that
   imports `http` is `lib/src/sync/cloudflare_sync_service.dart`. The default
   `syncServiceProvider` throws until an app overrides it
   (`lib/src/sync/sync_service_provider.dart`). `AuthNotifier` reads only the
   key store and the crypto service (`lib/src/state/auth_notifier.dart`), and
   `test/state/auth_notifier_test.dart` drives it with a mock key store and no
   network.
2. **The seed rule is plain BIP39.** Twelve English words, PBKDF2-HMAC-SHA512,
   2048 iterations, salt `mnemonic`, a 512-bit seed. Held by
   `lib/src/bip39/mnemonic.dart`. Pinned by `test/bip39/mnemonic_test.dart`
   and by the phrase-to-keys known-answer test in
   `test/crypto/key_derivation_test.dart`.
3. **The five legacy HKDF labels are frozen.** HKDF-SHA256, no salt, 32 bytes
   out, with these `info` strings: `openhearth.encryption.v1`,
   `openhearth.sync.encryption.v1`, `openhearth.auth.v1`,
   `openhearth.recovery.v1`, `openhearth.sync.channel.v1`. Held by
   `lib/src/crypto/key_derivation.dart`. Pinned by known-answer vectors in
   `test/crypto/key_derivation_test.dart` and
   `test/crypto/key_derivation_sync_test.dart`. Changing a label changes the
   key, and every backup made under the old key stops opening.
4. **A null `appDomain` is the legacy derivation, byte for byte.** A non-null
   one builds `openhearth.<appDomain>.<purpose>.v1`, must match `[a-z0-9]+`,
   and must not be a word that appears in a frozen label (such as `sync` or
   `auth`). Held by `_validateAppDomain` in
   `lib/src/crypto/key_derivation.dart`. Pinned by
   `test/crypto/key_derivation_domain_test.dart`.
5. **The sync key and the backup key are different keys.** A fault in one
   encryption path must not expose the other. Held by the separate labels in
   `lib/src/crypto/key_derivation.dart`. Pinned by "all derived keys are
   distinct" in `test/crypto/key_derivation_test.dart`.
6. **One cipher, used one way.** ChaCha20-Poly1305, a 32-byte key, a fresh
   random 12-byte nonce for every encryption, a 16-byte tag. A wrong key or a
   changed byte throws `CryptoException` and returns no plaintext. Held by
   `lib/src/crypto/envelope_cipher.dart`. Pinned by
   `test/crypto/envelope_cipher_test.dart`.
7. **The OHBK layout is fixed.** Four magic bytes `OHBK`, one version byte,
   one cipher-suite byte (`0x01`), a 12-byte nonce, a 16-byte tag, then the
   ciphertext. Held by `lib/src/backup/ghost_backup.dart`. Pinned by
   `test/backup/ghost_backup_test.dart`.
8. **A version 2 blob is bound to its purpose.** The six header bytes and a
   context label are authenticated with the ciphertext. A blob written for one
   purpose does not open under another label. The labels in this package are
   `ghost-backup/v1` (`lib/src/backup/ghost_backup.dart`) and `sync-dump/v1`
   (`lib/src/sync/sync_orchestrator.dart`). Pinned by the context and
   tampered-header tests in `test/backup/ghost_backup_test.dart` and by the
   ghost-context test in `test/sync/sync_hardening_test.dart`.
9. **Version 1 is read and never written.** `export` writes version `0x02`.
   `import` accepts `0x02` and the legacy `0x01`, which has no purpose
   binding. Held by `lib/src/backup/ghost_backup.dart`. Pinned by the version
   byte and legacy tests in `test/backup/ghost_backup_test.dart`.
10. **Export never writes a blob that import would refuse.** Both enforce the
    same 10 MB ceiling, and export checks before it encrypts. Held by
    `lib/src/backup/ghost_backup.dart`. Pinned by the oversized tests in
    `test/backup/ghost_backup_test.dart`.
11. **Derived keys live in memory only.** `AuthState` has no method that
    writes itself out, and it copies every key it is given
    (`lib/src/state/auth_state.dart`). The copying is pinned by
    `test/state/auth_state_test.dart`. The only secret that is stored is the
    phrase, through `SecureKeyStore` (`lib/src/storage/secure_key_store.dart`).
    The absence of a serializer is read from the code. No test asserts it.
12. **"I wrote it down" has to be shown.** `confirmSeedAcknowledged` accepts
    only a re-entered phrase that matches the stored one, and
    `generateSeedPhrase` refuses to replace an existing phrase unless the
    caller passes `force`. Held by `lib/src/state/auth_notifier.dart`. Pinned
    by `test/state/auth_notifier_test.dart`.
13. **An error does not carry the phrase.** Pinned for seed derivation by
    "deriveSeed error does not leak the raw phrase" in
    `test/bip39/mnemonic_test.dart`. The mismatch error's default message is
    generic and names no word (`lib/src/exceptions.dart`).
14. **While the sync layer exists, its guards stay.** The table allow-list is
    a required argument. A timestamp more than 24 hours ahead is clamped to
    now. Merged rows are sorted by id. One bad peer does not stop the others.
    Each peer is merged against the original base. Held by
    `lib/src/sync/three_way_merge.dart` and
    `lib/src/sync/sync_orchestrator.dart`. Pinned by
    `test/sync/sync_hardening_test.dart`, `test/sync/multi_peer_merge_test.dart`
    and `test/sync/sync_orchestrator_test.dart`.

## Honest scorecard: built and not built

A guiding light has to tell the truth about where the light reaches. This code
and its comments were written by an AI assistant. Treat them as a record of
what exists today, and verify a claim before you rely on it. When sources
disagree, the order of authority is reality, then tests, then code, then
comments, then prose docs such as this one.

As of November 2026, version 0.1.0. Every line below was checked by reading
the code and the test files. The suite under `test/` was not run for this
document.

**Real, with tests in the suite under `test/`:**

- **The Ghost tier is built.** Phrase generation and validation, seed
  derivation, the five keys, per-app domains, the cipher, the OHBK blob with
  both versions, and the auth state machine. Each has a test file under
  `test/bip39/`, `test/crypto/`, `test/backup/` and `test/state/`.
- **The whole chain in one test.** `test/e2e_chain_test.dart` goes from a new
  phrase to keys, to a backup, and back, and repeats the restore from the
  phrase alone.
- **The barrel file.** `test/barrel_public_api_test.dart` checks that the
  per-app domain provider, `deriveKey` and the OHBK round trip are reachable
  from the one public import.
- **The merge and the orchestrator, apart from the defect below.** Covered by
  `three_way_merge_test.dart`, `multi_peer_merge_test.dart`,
  `sync_hardening_test.dart` and `sync_orchestrator_test.dart` under
  `test/sync/`.

**Built and unproven:**

- **The real key store.** `test/storage/secure_key_store_test.dart` exercises
  a mock of the `SecureKeyStore` interface. No test in this package runs
  `FlutterSecureKeyStore` or pins its four storage key names.
- **The relay client.** `test/sync/cloudflare_sync_service_test.dart` runs it
  against a mock HTTP client. It has not been run against a relay, because no
  relay is deployed.
- **The default `syncServiceProvider`.** It throws by reading the code. No
  test asserts it.
- **Web.** The README says the cipher and both derivations run in pure Dart on
  the main isolate on web and will stall the page on large blobs. Nothing
  under `test/` covers web.
- **Outside review.** The repo records no review of the cryptography by anyone
  outside the project.

**Designed and not built:**

- **The Named tier is an enum value with no implementation.**
  `AuthTier.named` exists in `lib/src/state/auth_tier.dart`. There is no
  passkey dependency in `pubspec.yaml` and no code that uses the value.
- **Nothing sets the Sync tier either.** `AuthNotifier` only ever produces
  `AuthTier.ghost`, with or without a phrase. `AuthTier.token` is never
  assigned in `lib/`.
- **Two of the five keys have no user.** `authKey` and `recoveryKey` are
  derived and pinned, and nothing in `lib/` reads them.
- **No relay is deployed.** The README states this. This repo holds client
  code only, so the statement cannot be checked from here.
- **No biometric gate.** There is no `local_auth` dependency and no such code
  in this package.

**Known to be wrong:**

- **The sync layer ships with a defect that can drop a row.** The merge keeps
  no record of deletes. A row that is in the last synced base and in the local
  dump, and missing from a peer's dump, is read as deleted by that peer. A
  peer with a stale dump has simply not seen the row yet. The merge cannot
  tell the two apart, so a row made on one device can vanish on that device's
  second sync.
- **The test for it is skipped on purpose.** It is
  `test/sync/stale_peer_repro_test.dart`. A test run does not report the
  defect.
- **The defect is not fixed here.** The README, under "Status", gives the
  plan: replace this layer with an op log in a separate sync kernel where a
  delete is an explicit operation, port the scenario there, and delete
  `lib/src/sync/` when the first app moves. Until then the sync exports remain
  in the barrel file.
- **No lock file in the repo.** `pubspec.lock` is in `.gitignore`. The two
  cryptographic dependencies are pinned exactly (`cryptography: 2.9.0`,
  `bip39_mnemonic: 4.1.0`, held by `test/pubspec_pins_test.dart`), but their
  own dependencies still resolve on the day.
- **No CI file.** The repo has no workflow folder. Nothing runs the suite
  except a person or agent who types the command.
- **Sync statistics cover the last peer only.** In
  `lib/src/sync/sync_orchestrator.dart` the variable `aggregatedStats` is
  replaced on each round. With more than one peer, `SyncResult.stats` is the
  last round's numbers.
- **Comments point outside the repo.** Several doc comments cite a sync spec
  and an auth requirements document by name. Neither file is in this repo.

Keep that line bright. The path from twelve words to an opened backup is real
and has tests. Anything that crosses to a second device is client code with a
known defect and no relay. The Named tier is a name.

## Horizons (problems, no feature list)

Framed as problems on purpose. A dated feature list goes stale.

- **Lost words are lost data.** `generateSeedPhrase(force: true)` and
  `resetIdentity` both say so in their doc comments. How does a household
  recover without a server that holds something about it?
- **A delete has to be a fact.** Absence in a dump cannot mean "deleted". The
  plan in the README moves this problem to another codebase. The open part is
  the move itself: every app that calls the sync exports, and the day
  `lib/src/sync/` can go.
- **Which bytes are we trusting?** The two cryptographic packages are pinned,
  but with no lock file their own dependencies depend on the day they were
  resolved.
- **Old backups must keep opening.** The version 1 read path shows the cost of
  one format change. What is the rule for the next one, and how is it tested
  before it ships?
- **The real key store, proven.** How do we show, on each platform, that the
  phrase is stored where the wrapper says, and that the storage key names
  never drift?
- **What a named identity would add.** The enum has a third value. The open
  question is what it gives a household that the twelve words do not, while
  the Ghost tier stays whole.
- **Heavy work on web.** Derivation and large encryptions on the main isolate
  are slow in a browser.

## The name

**Sanctuary**: a place kept safe, where what is inside is not handed over. The
repo does not explain the name anywhere else, so take this as the plain
reading. The library is the part of each app that holds the household's keys.
`auth` is the identity model of the fleet (Ghost, Sync, Named). `core` means
no screens.
