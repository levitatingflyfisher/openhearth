# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

Guidance for AI coding agents (and humans) working in this repo. This is the
top-level map. Read it before non-trivial work.

**Read these two, in order, before you change anything load-bearing:**
1. [VISION.md](VISION.md): what must stay true and why (the invariants), and
   the honest scorecard.
2. [README.md](README.md): the public API table and, under "Status", the known
   defect in the sync code.

## Take the code as current-state

Every line of source and every comment here was written by an AI assistant.
Treat it as **an accurate record of what currently exists, offered with
gratitude and a grain of salt**. It is no specification and it is not
guaranteed correct. A comment that claims an invariant is a hypothesis until
you have checked it. When sources disagree, the order of authority is
**reality > tests > code > comments > prose docs**. Two live examples: the
storage test file exercises a mock of the key store interface, so the real
wrapper is untested here. And the doc comment on `AuthTier` describes three
working tiers, while the notifier only ever produces `ghost`. Confirm before
you rely.

## What this is

The shared identity library of the OpenHearth apps: a twelve-word household
phrase, the keys derived from it, and the encrypted OHBK backup envelope.
It is a Flutter package with no screens. Apps depend on it by path.
It also holds an older sync layer with a known defect, kept until its
replacement is in use.

## Non-negotiables (breaking one is a regression)

This is security code. A change that looks like a tidy-up can make every
existing backup unreadable.

- **Never change a frozen string or byte.** The five legacy HKDF labels in
  `lib/src/crypto/key_derivation.dart`, the BIP39 constants in
  `lib/src/bip39/mnemonic.dart`, the OHBK magic, version and cipher-suite
  bytes and the context label in `lib/src/backup/ghost_backup.dart`, the sync
  context label in `lib/src/sync/sync_orchestrator.dart`, and the four storage
  key names in `lib/src/storage/secure_key_store.dart`. A new meaning gets a
  new label or a new version. The old one stays readable.
- **Never edit a known-answer vector to make a test pass.** If a vector in
  `test/crypto/` or `test/bip39/` fails, the derivation changed. Fix the code.
- **The Ghost tier stays offline and account-free.** No new network call
  outside `lib/src/sync/`. No analytics, no crash reporter, no managed
  backend. The default `syncServiceProvider` keeps throwing.
- **No home-made cryptography.** Use the `cryptography` package through
  `EnvelopeCipher` and `KeyDerivation`. An app that needs a key from another
  secret calls `KeyDerivation.deriveKey` with its own label.
- **Keys stay in memory.** Do not add a serializer, a log line or an error
  message that carries a key, a seed or the phrase. Only the phrase is stored,
  and only through `SecureKeyStore`.
- **Never put a real phrase, key or seed in a test, a doc or a commit.** Test
  fixtures use made-up or published test values only.
- **Do not un-skip `test/sync/stale_peer_repro_test.dart` and call it fixed.**
  The defect is by design of this layer. The plan is in the README. Do not
  build new features on `lib/src/sync/`.
- **Do not present the Named tier or a deployed relay as real.** `AuthTier.named`
  is an enum value. No relay exists.
- **Cryptographic dependencies.** The fleet's rule is exact version pins.
  `cryptography` and `bip39_mnemonic` are pinned exactly, and
  `test/pubspec_pins_test.dart` fails on a range. Change a version only on
  purpose, in its own commit, with the full suite.
- **Everything public goes through the barrel file.** A consumer imports
  `package:sanctuary_auth_core/sanctuary_auth_core.dart` and nothing under
  `src/`.
- **TDD, always.** A failing test first. Every bug fix ships a regression
  test.
- **Atomic commits, one concern each.** The message states the why. No
  authorship attribution lines (`Co-Authored-By`, "Generated with"). This is
  deliberate project policy.
- **Never commit** `CLAUDE.md`, `GEMINI.md` or `docs/superpowers/`. They are
  local working files. This repo ships `AGENTS.md`.

## Where things are (progressive disclosure)

| You're touching… | Go to |
|---|---|
| **The public surface** | `lib/sanctuary_auth_core.dart` (the barrel file, the only public import); `test/barrel_public_api_test.dart` |
| **The twelve words** | `lib/src/bip39/mnemonic.dart` (generate, validate, seed derivation); `test/bip39/mnemonic_test.dart` |
| **Key derivation and labels** | `lib/src/crypto/key_derivation.dart` (the five keys, `appDomain`, reserved words, `deriveKey`); `test/crypto/key_derivation_test.dart`, `key_derivation_sync_test.dart`, `key_derivation_domain_test.dart`, `derive_key_test.dart` |
| **The cipher** | `lib/src/crypto/envelope_cipher.dart` (`EnvelopeCipher`, `CipherEnvelope`); `test/crypto/envelope_cipher_test.dart` |
| **The injectable crypto service** | `lib/src/crypto/crypto_service.dart` (`CryptoService`, `cryptoServiceProvider`, `sanctuaryAppDomainProvider`); `test/crypto/crypto_service_test.dart` |
| **The OHBK backup blob** | `lib/src/backup/ghost_backup.dart` (layout, versions, context binding, size ceiling); `test/backup/ghost_backup_test.dart` |
| **Auth state** | `lib/src/state/auth_notifier.dart` (load, generate, acknowledge, record backup, reset), `auth_state.dart` (the immutable state and the backup reminder), `auth_tier.dart` (the enum); `test/state/` |
| **Riverpod majors** | No generated code. `authNotifierProvider` is written by hand so the package builds against flutter_riverpod 2 and 3. Use only API both majors share: no `valueOrNull` (spell it `hasValue ? requireValue : null`), no codegen, no `retry:` argument |
| **Secure storage** | `lib/src/storage/secure_key_store.dart` (the interface, the real wrapper, the storage key names and the migration rule in its header comment), `secure_key_store_provider.dart`; `test/storage/secure_key_store_test.dart` (a mock only) |
| **Errors** | `lib/src/exceptions.dart` (the sealed `SanctuaryAuthException` family) |
| **Hex helpers** | `lib/src/util/hex.dart`; `test/util/hex_test.dart` |
| **Sync: the merge** | `lib/src/sync/three_way_merge.dart`; `test/sync/three_way_merge_test.dart`, `multi_peer_merge_test.dart`, `sync_hardening_test.dart` |
| **Sync: the cycle** | `lib/src/sync/sync_orchestrator.dart` (`SyncOrchestrator`, `SyncResult`, the sync context label); `test/sync/sync_orchestrator_test.dart` |
| **Sync: the known defect** | `test/sync/stale_peer_repro_test.dart` (skipped on purpose) and "Status" in `README.md` |
| **Sync: the relay client** | `lib/src/sync/sync_service.dart` (the interface), `cloudflare_sync_service.dart` (the HTTP client, the only `http` import), `sync_service_provider.dart` (throws by default); `test/sync/cloudflare_sync_service_test.dart` |
| **Sync: device id** | `lib/src/sync/device_id.dart`; `test/sync/device_id_test.dart`, `sync_state_integration_test.dart` |
| **The whole chain** | `test/e2e_chain_test.dart` (phrase, keys, backup, restore) |
| **Dependencies and SDK floor** | `pubspec.yaml` |
| **Lints** | `analysis_options.yaml` (`flutter_lints`, strict casts and strict raw types) |
| **Release notes** | `CHANGELOG.md` |

There is no `docs/` folder in this repo. The documents are `README.md`,
`VISION.md`, `AGENTS.md` and `CHANGELOG.md`.

## How to work here

```bash
flutter pub get
flutter test      # the suite under test/
flutter analyze   # lints from analysis_options.yaml
```

- **There is no CI file in this repo.** No workflow runs the suite.
  `flutter test` is the command the README gives. Run it yourself before a
  commit. The README names no lint command. `flutter analyze` is the standard
  one for the `analysis_options.yaml` that is here.
- **Use `flutter test`.** The package depends on Flutter, so `dart test` is
  the wrong runner.
- **One test is skipped on purpose.** A clean run does not mean the sync
  defect is gone.
- **The branch is `master`.**
- **A commit** is small, covers one concern, and its message says why the
  change was needed. Check `git config user.email` first. It must be the
  project's neutral address.
- **Tests that touch the notifier** override `secureKeyStoreProvider` with a
  mock, as `test/state/auth_notifier_test.dart` does. The platform keychain is
  not available in a test run.
- **`pubspec.lock` is not committed.** It is in `.gitignore`.

## When you're unsure

Prefer a failing test to a plausible fix. Prefer matching the surrounding code
to a new pattern. Prefer keeping data on the device to any convenience that
sends it off. On anything that touches a key, a label or the blob format,
stop and ask, or leave a `TODO` with the open question. A wrong guess here
costs a household its backups.
