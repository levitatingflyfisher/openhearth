# ADR-0001: A safety copy before every restore, broken state moved aside, and one plain notice

- **Status:** Proposed. Design only. It waits on three owner decisions; no code is written until they are answered.
- **Date:** 2026-11-01

## Context

A sweep of the fleet apps in November 2026 found three gaps that repeat from app to app.

1. **Restore replaces everything.** Each app's `BackupSerializer.restoreAll` wipes its tables and re-inserts the backup inside one transaction. A bad backup rolls back. A good backup of the wrong date, or an empty one, replaces the family's data. The sweep named Bulwark, Lullaby, Hatch and Reckon.
2. **Broken state either stops the app or is lost.** In Lullaby, Mantle, Lilt and porch, a corrupt database or state file stops the app opening. In PunctumTemporis, Lullaby, StillLife and Hatch, an unreadable saved value used to be replaced with an empty one and then written over; those cases were fixed one by one on the `defect-fixes` branches, each in its own way.
3. **Nobody is told.** Where broken state is now set aside, only the log says so.

The workshop rule for broken state is: never refuse to start on it; move it aside under a dated name, never delete it, start fresh, and report it.

**What this package already does.** `BackupController.commitRestore` takes a mandatory safety copy before it applies a restore. It exports the current data, saves it in the vault as an auto-pinned `preRestore` snapshot, reads it back and decrypts it, and refuses to touch any data if that fails. `snapshotBeforeWipe` gives "Clear all data" the same promise. So for an app that restores only through `commitRestore`, gap 1 is already closed, and the sweep's finding came from reading the apps' serializers alone.

**What is not known.** Whether every app restores only through `commitRestore` was not checked; the cross-repo search for it was refused. `BackupRepository.restore` and `BackupRepository.apply` are public and skip the safety copy, and an app can also call its own `restoreAll` directly. Reckon restores through its own `import_service`, and PunctumTemporis through its own backup service.

## Decision

These are answer A to owner decisions 4, 5 and 6. Each part stands alone, so the owner can accept one and not another.

### Part 1: every restore goes through the safety copy (decision 4)

- `commitRestore` and `snapshotBeforeWipe` stay the only ways to replace or wipe an app's data.
- `BackupRepository.restore` and `BackupRepository.apply` stop being public API: `apply` is reached only from `BackupController`, and `restore` is removed. There is one real user, so the break is clean.
- `oh_fleet_conformance` gains a check that fails when an app's `lib/` calls `restoreAll`, `BackupRepository.apply` or `BackupRepository.restore` outside its serializer and its tests.
- Apps with their own restore path (Reckon's import, PunctumTemporis' media restore) either move to `commitRestore` or take a snapshot through `snapshotBeforeWipe` first. Which apps need this is the first job once the owner answers.

The vault keeps the safety copy auto-pinned until the next restore replaces it, and the "Previous backups" sheet already lists it as "Safety snapshot". No new screen is needed for part 1.

### Part 2: broken state is moved aside, the app starts fresh (decision 5)

The package gains one small API that every app uses, so each app stops writing its own version.

- `setAsideFile(path)` renames an unreadable file in place to `<name>.unreadable-<UTC stamp>.<ext>`. It never deletes, never reuses a name, and throws without changing anything if the rename fails.
- `setAsideValue(store, key)` copies an unreadable stored value to `<key>.unreadable.<UTC stamp>` and only then clears the original. If the copy fails, the original stays.
- Each set-aside is written to a small record kept beside the vault (what, when, the new name). Set-aside items are never pruned automatically.

**The database.** When the app database fails to open, the app classifies the failure.
- A corrupt file ("file is not a database", or a failed `PRAGMA quick_check`) is moved aside with `setAsideFile`, together with its `-wal` and `-shm` files, and a fresh database is created.
- A passing failure (locked, disk full, permission) is not corruption. The app shows its existing error screen and retries; it moves nothing.

After a fresh start the vault is still there, because it lives outside the database. The notice in part 3 offers to restore the newest snapshot.

**Writes.** A file the app writes by hand goes to a temporary file in the same folder and is renamed over the target, as PunctumTemporis now does. The package exports this as `writeFileAtomic` so apps share one tested version.

**porch is outside this part.** Its state file is encrypted with the device identity, and a wrong key looks the same as damage. Starting fresh there drops the user's groups and touches the identity boundary, where porch's own guide says to ask. It needs its own question to the owner.

### Part 3: one plain notice (decision 6)

- On the first screen after a set-aside, the app shows one notice, once per event, through a package widget, `SetAsideNotice`.
- The draft wording is: "Some saved data could not be read. A copy is kept on this device, and the app started fresh. Nothing was deleted." It has two actions: "Restore from a backup", which opens Previous backups when the vault has a snapshot, and "OK".
- The notice is marked as seen in the set-aside record. It does not return after "OK".
- The words are a draft. They go to a blind reader before any user sees them, as the workshop asks for public copy.

## Tests it would need

Each test is written first and seen failing before its code.

**Part 1**
1. `commitRestore` on a vault whose save fails returns `snapshotFailed` and the serializer is never called. This already exists; it is kept.
2. A restore of an empty but valid backup leaves an auto-pinned `preRestore` snapshot whose contents equal the data before the restore.
3. Rolling back from that snapshot through the vault sheet brings the old data back and takes a new safety copy first.
4. `BackupRepository.apply` is not exported from `sanctuary_backup_ui.dart` (a compile-time test file that must fail to compile if it is).
5. The conformance check fails on a fixture app whose `lib/` calls `restoreAll` from a screen, and passes on one that calls it only from its serializer.

**Part 2**
6. `setAsideFile` renames to a dated name, leaves the bytes identical, and leaves no file at the old path.
7. Two set-asides in the same second get two different names.
8. A failed rename leaves the original file where it was and throws.
9. `setAsideValue` keeps the old value under the dated key before it clears the original; a failed copy leaves the original.
10. A database file of random bytes is moved aside with its `-wal` and `-shm` files, and the app opens on a fresh database.
11. A locked database is not moved aside and the existing error screen shows.
12. `writeFileAtomic` killed between write and rename (simulated by a throwing rename) leaves the old file whole.
13. The set-aside record survives an app restart and is not pruned by the vault's keep-N.

**Part 3**
14. After a set-aside, the first screen shows the notice once, and not again after "OK".
15. "Restore from a backup" opens Previous backups when a snapshot exists, and is hidden when the vault is empty.
16. Two set-asides in one start show one notice that covers both.
17. The notice text passes the fleet copy checks (no straight quotes, the banned words list).

Every app that adopts a part runs its full suite under `TZ=UTC` and under a daylight-saving zone, as the sweep did.

## Consequences

- **Buys:** a family can always get back the data they had a minute before a restore or a crash. One tested way replaces the per-app versions written during the sweep.
- **Costs:** a breaking change to the package's public API, a conformance check every app must pass, a new widget and its copy, and a migration of each app's own set-aside code onto the shared one.
- **Forecloses:** an app restoring without a safety copy, and an app quietly starting empty on unreadable data.

## Alternatives considered

- **Leave each app to its own fix (answer B to each decision):** the sweep showed the same gap written five ways, and the gap that was not yet found stays open.
- **Keep set-aside files inside the vault:** the vault prunes and is sealed under the device key; a broken file may be the very thing that cannot be sealed. They stay beside the original instead.
- **Delete broken state after a period:** against the workshop rule, and a family's only copy of something can be the broken one.
- **A screen listing every set-aside file:** more than a family needs; the notice and Previous backups cover the useful action.
