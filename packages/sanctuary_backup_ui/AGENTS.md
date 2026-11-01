# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

Guidance for AI coding agents (and humans) working in this repo. This is the
top-level map. Read it before non-trivial work.

**Read these two, in order, before you change anything load-bearing:**
1. [VISION.md](VISION.md): what must stay true, and the honest scorecard.
2. [README.md](README.md): how an app wires the package in, and the section
   "What leaves the device".

## What this is

The shared backup and restore screens of the OpenHearth apps, as a Flutter library.
An app supplies a `BackupSerializer` and a `SanctuaryBackupConfig`. The package supplies the controller, the snapshot vault and the screens.
The cryptography lives in `sanctuary_auth_core`, a sibling library in its own repo.

## Take the code as current-state, with a grain of salt

Every line of source and every comment here was written by an AI assistant.
Treat it as an accurate record of what exists today, offered with gratitude and
a grain of salt. It is no specification and is not guaranteed correct. A
comment that claims an invariant is a hypothesis to verify. The order of
authority is: reality, then tests, then code, then comments, then prose docs.

One live example. A comment in `lib/src/backup_serializer.dart` says the plain
text never leaves that interface unencrypted. The code in
`lib/src/backup_flow.dart` shares the same bytes as a plain JSON file when the
user asks. The code is right. The comment is known to be stale.

## Non-negotiables (breaking one is a regression)

- **A restore saves the current data first, or it does not run.** Do not
  reorder `commitRestore` in `lib/src/backup_controller.dart`. The snapshot is
  saved, read back and decrypted before `apply` is called. A failed snapshot
  returns `RestoreOutcome.snapshotFailed` and touches no data.
- **Open before you ask, and ask before you write.** `prepareRestore` writes
  nothing. Wrong words must never reach the confirm dialog or cause a snapshot.
- **An export that does not read back is a failure.** Keep the read-back in
  `exportBackup`, and keep reporting the failure to the user.
- **The vault keeps the rollback.** In `lib/src/backup_vault.dart` the new
  snapshot is stored before the old one loses protection. A user pin is never
  changed by the vault. In `lib/src/file_vault_store.dart` the blob files are
  the truth and a rebuilt entry comes back pinned.
- **Never overwrite recovery words that are on the device.** Setup stores
  words only after the user says they wrote them down.
- **No network call.** Nothing leaves the device unless the user taps for it.
  If you add or change a way out, update "What leaves the device" in the README
  in the same change.
- **No cipher code here.** Keys, words and the file format come from
  `sanctuary_auth_core`. A key from a human password must use Argon2id, and
  `test/passphrase_guard_test.dart` fails without it.
- **Never open or print a real key, seed or secret.** The tests use made-up
  words and the fakes in `lib/testing.dart`.
- **Keep the public names stable.** Many apps import this package. Apps switch
  over `VaultLabel` and `RestoreOutcome`, and every app implements
  `BackupSerializer`, so a new value or member breaks them. Note any change in
  `CHANGELOG.md`.
- **Bytes only, and no code generation.** Files move as bytes so the web build
  stays clean. State is plain `flutter_riverpod`.
- **Test first.** Every fix ships a regression test. User-facing text is plain
  and says what will happen.
- **Never commit** `CLAUDE.md`, `GEMINI.md` or `docs/superpowers/`. This repo
  ships `AGENTS.md`.

## Where things are (progressive disclosure)

| You are touching | Go to |
|---|---|
| **What the package exports** | `lib/sanctuary_backup_ui.dart` (the barrel file) |
| **The app's side of the contract** | `lib/src/backup_serializer.dart` (`BackupSerializer`, `PreviewableBackupSerializer`, `BackupSchemaException`). Its comment about plain text never leaving unencrypted is known to be stale |
| **Per-app config and the providers an app overrides** | `lib/src/backup_config.dart` (`SanctuaryBackupConfig`, the throw-by-default providers, `vaultStoreProvider`, `backupVaultProvider`) |
| **Restore, export, snapshots before a restore or a wipe** | `lib/src/backup_controller.dart` (`prepareRestore`, `commitRestore`, `exportBackup`, `snapshotBeforeWipe`, `runStartupMaintenance`, `RestoreOutcome`) |
| **Sealing and opening a blob** | `lib/src/backup_repository.dart` (`export`, `open`, `apply`, bound to the app's `aadContext`) |
| **What the user sees and taps, in order** | `lib/src/backup_flow.dart` (`BackupFlow`: setup, show words, export, plain JSON export, restore, remove words, and every confirm dialog's text) |
| **The JSON envelope and the preview counts** | `lib/src/backup_envelope.dart` (`BackupEnvelope.wrap`, `unwrap`, `describe`, `BackupManifest`) |
| **Snapshot retention: stamps, keep count, pins** | `lib/src/backup_vault.dart` (`BackupVault`, `VaultEntry`, `VaultLabel`, the `VaultStore` interface) |
| **Snapshot files and the index** | `lib/src/file_vault_store.dart` (`FileVaultStore`, `VaultFileApi`) |
| **Where snapshots live on each platform** | `lib/src/vault_store_platform.dart` (picks one), `lib/src/vault_store_io.dart` (app documents folder), `lib/src/vault_store_web.dart` (the browser's private file system, no test here) |
| **Recovery words on the web, per app** | `lib/src/app_scoped_key_store.dart` (`AppScopedSecureKeyStore`, `legacyPhraseOwnedBy`, `appScopedKeyStoreOverride`) |
| **The "Finish setup" state** | `lib/src/backup_setup_status.dart` (`BackupSetupStatus`, the reminder store, the thirty-day return) |
| **The ready-made settings section** | `lib/src/widgets/backup_settings_section.dart` (which tile shows in which state; the plain JSON tile shows in every loaded state) |
| **The other screens and dialogs** | `lib/src/widgets/` (`backup_setup_reminder.dart`, `backup_vault_sheet.dart`, `seed_phrase_modal.dart`, `phrase_entry_dialog.dart`, `phrase_re_entry_dialog.dart`) |
| **Fakes for an app's own tests** | `lib/testing.dart` |
| **Restore safety tests** | `test/backup_restore_safety_test.dart`, `test/backup_flow_test.dart` |
| **Vault tests** | `test/backup_vault_test.dart`, `test/file_vault_store_test.dart` |
| **Other unit tests** | `test/` (each file is named after the source file it covers, plus `passphrase_guard_test.dart`) |
| **Widget tests** | `test/widgets/` (one file per widget) |
| **Dependencies and version** | `pubspec.yaml`, `CHANGELOG.md` |
| **Lints** | `analysis_options.yaml` |

Comments in `lib/` cite sections of two specification documents by name. Those
documents are not in this repo.

## How to work here

```bash
flutter pub get
flutter test       # the suite under test/
flutter analyze    # the lints in analysis_options.yaml
```

- **There is no CI file in this repo.** No workflow runs the suite for you.
  Run it yourself, from the repo root, before you commit. The passphrase guard
  test reads `lib/` by a relative path.
- **This is a Flutter package.** Use `flutter test`. The tests import
  `flutter_test`.
- **`sanctuary_auth_core` must be a sibling checkout.** `pubspec.yaml` depends
  on it by the path `../sanctuary_auth_core`. Without it, `flutter pub get`
  fails. `pubspec.lock` is not committed.
- **The branch is `master`.**
- **Commits are small, one concern each.** The message states the why. Recent
  subjects start with the area, for example `README:` or `Changelog:`. Commit as
  the repo's configured neutral identity, and check `git config user.email`
  first. No AI attribution lines (`Co-Authored-By`, "Generated with"). This is
  project policy.
- **New test?** Override the providers with the fakes in `lib/testing.dart`,
  as the existing tests do, so the test does not need the system keychain.

## When you are unsure

Prefer a failing test to a plausible fix. Prefer matching the code around you to
a new pattern. Prefer keeping data on the device to any convenience that sends
it off. If a comment and the code disagree, trust the code, check it with a
test, and say what you found.
