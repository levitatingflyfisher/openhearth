# Limitations

Read this before adopting Lullaby or building on it. An honest list of what it
does **not** do, as of the current tree (past the 1.0.0 release; see Unreleased
in [CHANGELOG.md](../CHANGELOG.md)). For the built-vs-aspirational split see
[VISION.md § Honest scorecard](../VISION.md#honest-scorecard--built-vs-aspirational).

## It is not a medical device

Lullaby is a **record-keeping tool**, not a diagnostic one. The WHO percentile
curves are reference standards for orientation, not an assessment. Nothing in the
app is medical advice. Anything concerning goes to a paediatrician — the doctor
summary exists to *help that conversation*, not replace it.

## Two-phone sync is young

Sync between two parents' phones ships, off by default
([ADR-0007](adr/0007-household-sync.md)): phone to phone on the same Wi-Fi with a
code, or through a relay the household chooses. Its limits today:

- **The project does not run a relay.** A household that wants sync away from
  the same Wi-Fi has to run or choose its own.
- **Same-Wi-Fi sync works in the Android app only.** In a browser, sync goes
  through a relay.
- **Photos do not sync.** A baby's photo stays on the phone that took it.
- **Restore is refused while sync is on.** Restoring a backup is a full replace
  and cannot travel through the sync log.
- **The 12 recovery words are typed once on the second phone.** The same-Wi-Fi
  code pairs one session; it does not replace the words.
- It has been run on an emulator and in a browser, not yet on two real phones
  (see [VISION.md § Honest scorecard](../VISION.md#honest-scorecard--built-vs-aspirational)).

## No account recovery

By design there is no account, so there is no "reset password" email. If a parent
sets up an encrypted backup and **loses the seed phrase, the backup is
unrecoverable.** If the phone is lost with no backup, the data is gone. This is
the deliberate cost of holding your own keys ([ADR-0001](adr/0001-local-first-no-account.md),
[ADR-0004](adr/0004-encrypted-backup-seed-phrase.md)).

## Known incompatibility: pre-rewire (stub-era) backups

Lullaby's encrypted-backup feature originally ran on an in-repo CI stub for
its crypto, before this codebase was re-wired onto the real, audited
`sanctuary_auth_core` package. If you ever exported an `.ohbk` file from a
build that predates the re-wire, **that file cannot be restored** by the
current app. The stub's key derivation (PBKDF2-HMAC-SHA256/1000 iterations)
is a different algorithm from the real core's (PBKDF2-HMAC-SHA512/2048 →
HKDF), so the same recovery phrase now derives a different key — the OHBK
wire format itself didn't change, but the key needed to open the ciphertext
isn't recoverable from the phrase alone.

In practice we have no known affected user: the stub-era build kept its keystore
in-memory only, so a seed phrase never survived an app restart, meaning there
was no persistent stub-era identity or backup corpus to begin with — any such
export was already unrestorable under the stub itself by the time the app was
closed. Restoring on the real core is the first release where a backup you
make today will still work tomorrow. See
`test/unit/features/sanctuary_backup/stub_compat_gate_test.dart` for the
specific proof (wire format compatible, key derivation is not).

## The production crypto is now vendored via sibling packages

The encrypted-backup module (`sanctuary_auth_core`) and its Flutter UI layer
(`sanctuary_backup_ui`) are consumed as path dependencies on sibling
repositories (`../packages/sanctuary_auth_core`,
`../packages/sanctuary_backup_ui`), not a private out-of-repo package and not
an in-repo stub. The in-repo CI stub (`ci/auth_stub/`) that this app
previously shipped in production has been removed; CI now clones the real
sibling packages instead.

## The local database file is not itself encrypted

Data at rest lives in a plain SQLite file in the app's private storage.
Confidentiality of that file rests on **device full-disk encryption and the OS app
sandbox**, not on app-level encryption — only the *backup* file is encrypted.
There is also **no in-app PIN or biometric lock**: anyone holding the unlocked
device can open the app. See [privacy-model.md](privacy-model.md).

## Feature gaps

- **No reminders or notifications** — the app does not schedule feed/medicine
  reminders.
- **A "named" account tier** exists in the auth enum but is not implemented; only
  the ghost tier runs. Sync needs no account.
- **Screenshots** are still "coming soon" in the README.

## Not yet published

The Android `applicationId` is `com.openhearth.lullaby`, but the release build
is still signed with the debug key. Publishing to an app store requires a
release signing key, and there is no release workflow yet (the only workflow is
`.github/workflows/ci.yml`).

## CI coverage is partial

CI runs `flutter analyze`, a web release build and `flutter test` on **one
Linux runner**. The web bundle is compiled but not opened in a browser, and the
Android APK, iOS and Linux desktop builds are **not** built by CI, so a
platform-specific regression could land without CI catching it.
