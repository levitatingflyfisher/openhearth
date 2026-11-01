# Vision

> The north star for `sanctuary_backup_ui`. If you (person or agent) are about to
> change something load-bearing, read this first. It says what must stay true and
> which file or test holds it. For where things are, see [AGENTS.md](AGENTS.md).
> For how an app wires the package in, see the [README](README.md).

## The one idea

**Every app in the fleet gets the same backup and restore, and a restore can be
rolled back.**

An app writes one serializer and one config object. The package supplies the
rest: the recovery words on screen, the encrypted `.ohbk` file, the restore with
its preview, and a snapshot of the current data that is saved before anything is
replaced. A household learns backup once, and it works the same way in every app.

## What this is

A Flutter library of backup and restore screens for the OpenHearth apps, which
are free household tools that keep their data on the device. It was taken out of
one app's backup feature and made to work for any of them.

```
  the app supplies             this package                 the user ends up with
 -----------------------    -------------------------    --------------------------
  BackupSerializer           controller and flow          an encrypted .ohbk file
  (dumpAll / restoreAll) --> snapshot vault           --> snapshots kept on the device
  SanctuaryBackupConfig      screens and dialogs          a restore that can be undone
```

The cryptography is in another library. This package depends on
`sanctuary_auth_core`, which lives in its own repo and supplies the twelve
recovery words, the key derivation, the cipher and the OHBK file format. This
package adds the flow around them and holds no cipher code of its own.

An app can use it in two ways. It can drop the ready-made `BackupSettingsSection`
into its settings screen. Or it can draw its own tiles and call the same
`BackupFlow` methods that the section calls.

## The invariants (do not break these)

Each one is held today by the file or test named beside it. Breaking one is a
design regression.

1. **A restore saves the current data first, or it does not run.**
   `BackupController.commitRestore` saves a snapshot of the current data to the
   vault before it applies the backup. If the save fails it returns
   `RestoreOutcome.snapshotFailed` and touches nothing. Held by
   `lib/src/backup_controller.dart`. Tested in
   `test/backup_restore_safety_test.dart` (the `commitRestore` group and the
   one-shot wrapper group) and, for what the user sees, in
   `test/backup_flow_test.dart`. This holds for every restore that goes through
   `BackupController`, which is the path of every screen in this package.
2. **The snapshot is read back before the restore goes on.**
   `_saveVerifiedRollback` in `lib/src/backup_controller.dart` reads the stored
   bytes again and decrypts them under the same key before any data is replaced.
   `test/backup_restore_safety_test.dart` checks that the stored snapshot
   decrypts to the data that was there before the restore. No test makes a
   save succeed and the read-back then fail, so that branch is held by the code
   alone. The same method serves `snapshotBeforeWipe`, the snapshot an app takes
   before "Clear all data".
3. **A backup is opened before anything is confirmed or written.**
   `prepareRestore` decrypts and describes the backup and writes nothing.
   `BackupRepository.open` in `lib/src/backup_repository.dart` never calls the
   serializer. Wrong words stop the flow before the confirm dialog, so they
   never cause a snapshot. Tested in `test/backup_restore_safety_test.dart`
   (the `open / apply` and `prepareRestore` groups) and
   `test/backup_flow_test.dart` (wrong key leads to word entry before any
   confirm).
4. **An export counts only when its own bytes open again.**
   `BackupController.exportBackup` decrypts and parses the blob it just made
   and returns null if that fails. Held by `lib/src/backup_controller.dart`.
   Tested in the `exportBackup` group of `test/backup_restore_safety_test.dart`.
5. **The vault keeps the rollback.** `BackupVault.save` in
   `lib/src/backup_vault.dart` stores the new snapshot before the older rollback
   loses its protection. The newest pre-restore snapshot is protected from
   pruning. A snapshot the user pinned is never pruned and never unpinned by
   the vault. The keep count cannot go below one. Tested in
   `test/backup_vault_test.dart`.
6. **A lost or damaged index does not lose a snapshot.** In
   `lib/src/file_vault_store.dart` the blob files are the truth and the index is
   a cache. Entries rebuilt from the files come back pinned, and index writes
   run one at a time. Tested in `test/file_vault_store_test.dart`.
7. **A backup made for one app does not open in another.** Every blob is bound
   to the app's `aadContext` in `lib/src/backup_repository.dart`. Tested in
   `test/backup_repository_test.dart`.
8. **Recovery words already on a device are never overwritten.**
   `saveSeedPhrase` and `_maybeAdoptPhrase` in `lib/src/backup_controller.dart`
   both check the key store first. Tested in `test/backup_flow_test.dart` (the
   setup consent group) and `test/backup_restore_safety_test.dart` (the
   restore-adopt group).
9. **Setup stores the words only after the user says they wrote them down.**
   `BackupFlow.runSeedSetup` in `lib/src/backup_flow.dart` drafts the words,
   shows them, and saves them only on "I've written this down". Tested in the
   setup consent group of `test/backup_flow_test.dart`.
10. **On the web, one app's words and snapshots stay apart from another's.**
    The fleet's web apps share one origin. `AppScopedSecureKeyStore` in
    `lib/src/app_scoped_key_store.dart` names every entry by app, and
    `vaultStoreProvider` in `lib/src/backup_config.dart` scopes the vault folder
    by app. The key store is tested in `test/app_scoped_key_store_test.dart`.
    The vault scope is held by the code and has no test of its own. The key
    store part holds only for an app that adds `appScopedKeyStoreOverride()`.
11. **No key is derived from a human password without Argon2id.** The words are
    made by the machine, which is why the present key derivation is enough.
    `test/passphrase_guard_test.dart` reads every file under `lib/` and fails if
    password wording appears without Argon2id in the same file.
12. **Nothing leaves the device until the user asks.** No file under `lib/`
    imports a network client, and `pubspec.yaml` lists none. The three things
    that can leave, each on a tap, are listed in the README under "What leaves
    the device". This is held by the code as read. No test checks it.
13. **A missing override fails loudly.** The config and serializer providers in
    `lib/src/backup_config.dart` throw with a message that names the fix.
    Tested in `test/backup_config_test.dart`.

## Honest scorecard

As of version 0.3.0, November 2026. Every line below was checked by reading the
code and the tests. Nothing was built or run for this page, so "tested" means
that a test for it is in the suite under `test/`. No test file in that folder
carries a `skip:` argument.

**Real and tested:**
- The two-step restore: open and preview, then confirm, then snapshot, then
  apply. The preview shows the backup's age and row counts beside the counts on
  the device.
- The snapshot vault: stamped snapshots, a keep count (ten by default), user
  pins, one protected rollback at a time, and a copy of each manual export.
- The export read-back, and the freshness snapshot that
  `runStartupMaintenance` takes when the newest snapshot is older than seven
  days.
- The pre-wipe snapshot (`snapshotBeforeWipe`) with its three outcomes.
- Adopting typed words after a restore on a device that had none.
- The envelope helper (`BackupEnvelope`) and its reading of the older shapes
  that apps wrote by hand. See `test/backup_envelope_test.dart`.
- The file store on a real temporary folder, and the index repair, in
  `test/file_vault_store_test.dart`.
- The screens and dialogs under `lib/src/widgets/`, each with a widget test
  under `test/widgets/`, including layout at a narrow width with large text.
- The "Finish setup" reminder and its thirty-day return after a dismissal.

**Built, and unproven or limited:**
- **The plain JSON export.** `BackupSettingsSection` shows an "Export as plain
  JSON" tile whenever the section has loaded, with or without recovery words.
  The section's only parameter is its title, so an app that uses the ready-made
  section cannot hide the tile. A tap opens a confirm dialog titled "Export
  unencrypted copy?". On confirm, `BackupFlow.runPlaintextExport` hands the
  exact bytes of `serializer.dumpAll()` to the system share sheet as
  `<appId>-data-<date>-UNENCRYPTED.json`. The file is not encrypted. One widget
  test finds the tile, in the state without words. The dialog, the cancel path
  and the shared bytes have no test.
- **The steps that call the platform.** `runExport` is tested against a mocked
  share channel: a completed share stamps "Last backup", and a dismissed or
  unavailable sheet stamps nothing. No test opens a real share sheet. The file
  picker in `runRestore` has no test here; the restore tests enter one step
  later, at `restorePickedBlob`.
- **The web vault.** `lib/src/vault_store_web.dart` stores snapshots in the
  browser's private file system. It has no test in this repo. In a browser
  without that storage, the design is that the snapshot fails and the restore
  is refused. That path is read from the code and is unproven.
- **The recovery words stay off the share sheet and the clipboard.** The
  package shows them on screen and stores them through the key store of
  `sanctuary_auth_core`. This is true by reading. No test checks it.
- **The app's half of the contract.** `restoreAll` must replace data in one
  transaction and reject a newer schema. The package asks for this in
  `lib/src/backup_serializer.dart` and cannot check it.
- **Paths that skip the safety steps.** `BackupRepository.restore` and `apply`
  are public and take no snapshot. `BackupController.generateSeedPhrase`
  stores new words at once, and is kept for apps that call it directly. The
  screens in this package use neither.
- **A rollback can need other words.** When a restore is prepared with typed
  words on a device that has its own, the snapshot is sealed under the typed
  words. The confirm dialog says so.
- **No snapshot without words.** `snapshotBeforeWipe` returns `noKey` on a
  device with no recovery words, and writes nothing.
- **Web apps that have not added the override** share one set of recovery
  words in a browser. See the README.
- **No automated check runs in this repo.** There is no CI file. The suite
  runs when someone runs it.

**Designed and not built:**
- **Plain JSON import.** The README leaves it to each app, because a restore
  from an unsigned file can be tampered with.
- **A device lock in front of "Show my recovery words".** The package has none
  of its own. A confirm dialog is the only gate, and an app with a lock can put
  it in front of the call.
- **Use outside the fleet.** `pubspec.yaml` sets `publish_to: 'none'`, and the
  package is consumed by a path to a sibling folder.

**Known to be wrong:**
- A comment in `lib/src/backup_serializer.dart` says the plain text never
  leaves that interface unencrypted. The plain JSON export does exactly that.
  The code is right and the comment is stale.
- The class comment in `lib/src/widgets/phrase_entry_dialog.dart` still lists
  the setup check as one of its uses. Setup now uses `PhraseReEntryDialog`.
- The class comment in `lib/src/widgets/seed_phrase_modal.dart` says the sheet
  closes only on "I've written this down". Setup now also offers "Not now".
- A comment in `lib/testing.dart` names a browser database that the web vault
  does not use.
- Comments across `lib/` cite sections of two specification documents that are
  not in this repo. A reader with only this repo cannot follow them.

Keep the line clear. The restore path, the vault and the screens are real and
have tests. Anything that crosses into the platform, the browser, or an app's
own serializer is unproven here.

## Horizons, as open problems

These are problems to solve. None has a date.

- **Near.** Prove the unproven steps: the plain export flow, the share sheet
  and file picker steps, and the web vault in a real browser. Bring the stale
  comments back in line with the code. Decide where the cited specifications
  should live so that this repo can be read alone.
- **Mid.** The package trusts each app's serializer to restore in one
  transaction and to reject what it cannot read. Find a way to check that
  contract from here. Find a way to notice a web app that has not scoped its
  key store.
- **Far.** The twelve words are the only way back to the data on a new device.
  If the paper is lost and the device is lost, the data is lost. Any answer has
  to keep the rule that no server holds a key.

## The name

`sanctuary_backup_ui` is a plain name. It is the backup screens that sit on top
of `sanctuary_auth_core`, the fleet's identity library, and it shares that
library's first word.

## A grain of salt

This code, its comments and this page were written by an AI assistant. Take them
as a record of what exists today, offered with a grain of salt. Where sources
disagree, the order of authority is: reality, then tests, then code, then
comments, then prose docs such as this one. Verify a claim before you rely on
it.
