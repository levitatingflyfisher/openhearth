# How-to: back up & restore

Task-oriented. Your whole diary (clips, thumbnails, cropped faces, and the
`metadata.json` index) is portable as one file, a ZIP locked with your 12
recovery words. This is how you move to a new phone, keep an off-device copy,
or share a diary. Implemented in `lib/services/backup_service.dart`.

## Create a backup

In-app: **Settings → Backup / Restore → Create Backup**.

- **The first time,** the app shows 12 recovery words and asks you to type
  them back from paper (the shared sheets every OpenHearth app uses). Stop at
  either step and no backup is made. The words then stay in this phone's
  keychain, and every later backup uses them.
- **Native:** writes `onesecond_backup_<timestamp>.ohbs` into the app's own
  storage, then offers two choices: **Save to Device** (a folder you pick) or
  **Share** (the system share sheet, which can hand the file to any app, cloud
  or email you choose).
- **Web:** triggers a browser download of the same `.ohbs` file.

On Android every step goes file to file, so a library of many gigabytes needs
no more memory than a small one: the ZIP is streamed (video and pictures
stored as they are, the JSON deflated), sealed in 1 MiB chunks, and then
opened again chunk by chunk before the app says "verified". Two steps still
hold the whole file in memory: the web build (the browser hands over bytes)
and **Save to Device** (`file_picker` takes bytes on Android). **Share**
streams. The format is in `lib/services/backup_stream_cipher.dart`.

Inside the lock is a ZIP holding:

```
metadata.json           # the index (clips, compilations, knownPeople)
settings.json           # allowlisted settings (theme, reminders, pins…)
clips/<file>.mp4        # source clips
thumbnails/<file>.jpg   # thumbnails
faces/<name>.jpg        # cropped face references (native only)
compilations/<file>.mp4 # montage videos (on by default, toggleable)
```

`getBackupSize()` estimates the total up front so the UI can show it.

### Montages travel too

Montages are the point of the app, so the finished MP4s ride along by
default — the **Include montage videos** switch next to the size estimate
opts a backup out when size matters. Each compilation row also carries its
*recipe* (clip-audio level and music segments with timing/volume), so
re-opening a montage seeds the compile controls exactly as you left them.

On restore, montage files are extracted into the app-private `compiled/`
dir and each row is re-pointed there. A row whose file didn't travel (old
backups, or a montage whose file was already gone at pack time) still
restores; opening it shows a quiet notice — the gallery usually still has
the original copy, and COMPILE rebuilds it from the clips.

> **The backup is locked with your recovery words.** With the file and the
> words, anyone can watch the clips and see their dates, places, tags, and the
> names and face pictures of people you've named. Without the words nobody can
> open it, you included, so keep them on paper. The Backup screen says so above
> the button, before the file exists (`BackupRestoreScreen.backupFileNotice`).
> See [privacy-model.md](../privacy-model.md).

## Check before restoring

**Restore → pick a backup** (`.ohbs`, or a plain `.zip` made before backups
were locked) first runs `prepareRestore`. A locked file is opened with this
phone's words; when the phone has none, or they do not open it, the app asks
for the 12 words the file was made with. On a new phone, words that open a
backup are kept. The file is decrypted once, in pieces, to a temporary ZIP that
is always removed afterwards; a file that does not verify to its last chunk
(wrong words, or changed or cut short) is refused before anything is touched.
The app then shows the clip count, date range, size, face count, and
compilation count *before* you commit. Reading the archive here also runs the
safety ceilings (below), so a hostile file is refused at this step.

## Restore: merge vs. replace

Two modes:

- **Merge (default)** — adds clips, compilations, and people from the backup that
  aren't already present (deduplicated by `id`), keeping your current diary. Safe
  to run against a diary you're still using; re-running the same backup won't
  duplicate anything.
- **Replace** — overwrites existing files and metadata with the backup's. Clips
  that are not in the backup stop appearing in the app, but their video files
  stay on the device.

After extraction the metadata is reloaded and the calendar refreshes.

## Previous snapshots (roll back a restore)

Before every restore, in either mode, the app saves a snapshot of the journal
index (`metadata.json`) and your settings. If that snapshot cannot be saved, the
restore is refused and nothing is touched. The app also saves one quietly after
launch when the newest snapshot is more than 7 days old, or when there is none.

Snapshots are listed under **Previous snapshots** on the Backup & Restore
screen. Each one can be restored or deleted there. Restoring one rolls the index
and settings back and first saves a snapshot of the current state, so you can
change your mind again. A restore never deletes clip files, so a rollback covers
everything a restore can change.

Snapshots are plaintext files in the app's own storage (`metadata_vault/` under
the app documents directory on Android, OPFS on web). They hold no video and the
app offers no way to export them. The oldest are pruned as new ones arrive.
Implemented with the vault from the shared `sanctuary_backup_ui` package, in
`lib/services/backup_service.dart`, `lib/services/snapshot_serializer.dart` and
`lib/widgets/metadata_snapshots_section.dart`.

## What the safety checks do (and why a restore might refuse)

A backup you *received* is untrusted input
([ADR-0005](../adr/0005-untrusted-backup-hardening.md)). Restore enforces:

- **Zip-bomb ceilings**, checked against the archive's *declared* sizes **before**
  decompression: ≤ 50 000 entries, ≤ 2 GB per file, ≤ 8 GB total. A `BackupTooLargeException`
  means the archive exceeded one of these — split a legitimately huge backup.
- **ZIP-Slip rejection** — entries whose paths contain `..`, `.`, or empty
  segments are skipped, so nothing is written outside the media dirs.
- **Metadata path pinning** — every restored clip/thumbnail/compilation path is
  rewritten to point inside your own `clips/`/`thumbnails/`/`compiled/` dirs
  (basename only), and unsafe `knownPeople` names are dropped. A crafted backup
  therefore can't aim the app's file operations (share, delete, the next
  backup's reads) at your other files.

If a restore silently skips some entries, it's these checks doing their job.
