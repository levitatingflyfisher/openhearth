# ADR-0007: Lock the backup with the recovery words, and stream it

- **Status:** Accepted
- **Date:** November 2026 (owner's ruling, board-0167)

## Context

The backup was a plain ZIP by design. The owner recalled that encryption
had been dropped because the backups are too big, and ruled: encrypt them
like the other fleet apps only if it works at real size (stream or chunk
it, test with a backup of several GB, check memory stays flat and restore
works); otherwise keep the plain ZIP.

Two things were too big. The shared OHBK v2 envelope in
`sanctuary_auth_core` seals one buffer and refuses anything over 10 MB, so
it cannot carry a PT library at all. And PT's own pipeline held the whole
backup in memory several times over (every clip read into a list, the ZIP
encoded, copied, decoded again to verify; restore read and decoded the
picked file whole), so a multi-GB library could not back up or restore on
a phone, plain or not.

## Decision

- **OHBS, a chunked stream format** (`lib/services/backup_stream_cipher.dart`):
  a 44-byte header (magic, version, suite, chunk size, random 32-byte salt),
  then 1 MiB chunks, each sealed with ChaCha20-Poly1305 from the
  `cryptography` package the shared core uses (pinned exact, 2.9.0). The
  nonce is the chunk index; the AAD binds the header, the index and a final
  flag, so a changed, dropped, reordered or cut-off chunk fails.
- **The key comes only from the shared core** (`lib/services/backup_key.dart`):
  BIP39 seed, HKDF with app domain `punctum`, then a per-file key from the
  salt under the label `openhearth.punctum.backupstream.v1`. The words are
  kept in the shared app-scoped keychain slot and set up with the shared
  sheets. PT stays off Riverpod: it uses the widgets and store directly.
- **File to file on Android** (`lib/platform/backup_files_native.dart`): the
  ZIP is streamed from the clip files (media stored, JSON deflated), read
  back from disk, sealed, and opened again chunk by chunk before it counts.
  Restore decrypts once to a temporary ZIP, checks the ceilings
  (ADR-0005), extracts each entry in pieces, and always removes the copy.
- **Measured** before it was built in: 100 MB, 1 GB and 4 GB of random
  bytes round-tripped byte-exact with peak memory 87 to 99 MiB at every
  size, at about 20 MB/s per direction on one desktop core.

- **Measured again through the real backup and restore**
  (`test/size/backup_at_size_test.dart`, synthetic 2 MiB clips, desktop,
  flutter test): 100 MB, 1 GB and 4 GB libraries each restored with every
  clip matching by SHA-256. Peak memory of the whole test process was 279,
  306 and 345 MiB: 40 times the data, 66 MiB more, growing with the clip
  count (journal and ZIP directory), not the bytes. The 4 GB backup took
  427 s and the restore 290 s.

## Consequences

- A shared or lost backup file shows nothing without the words.
- The household must keep 12 words on paper. Lose them and every locked
  backup is lost too. This is the cost the owner accepted for the fleet.
- Two steps still hold a whole file in memory: the web build (the browser
  hands over bytes) and Save to Device on Android (`file_picker.saveFile`
  takes bytes). Share streams.
- Phone speed is unmeasured: pure-Dart ChaCha20 on a phone core is slower
  than on the desktop core measured here, by an amount only a device run
  can tell.
- Old plain ZIPs still restore, through the same path.

## Alternatives considered

- **OHBK v2 as it is:** refused by its own 10 MB ceiling.
- **Keep the plain ZIP** with the line "A backup needs no recovery words.
  Copy the file over and select it here.": the owner's fallback, for the
  case where the size problem stood. It did not.
- **Encrypt on top of the old in-memory pipeline:** the cipher would stream,
  but the backup around it would still fail at a few GB.
