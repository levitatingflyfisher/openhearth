# How to back up and restore WeatherGlass

WeatherGlass keeps your saved places and settings on your device, with no
account and no server of ours to lose them to. Android may also back them up to
Google if the phone's owner allows it in Android settings; the recovery words are
never part of that. The encrypted backup is the private choice, and it exists so
that losing the device doesn't mean losing your places.

## What's in a backup

A `.ohbk` file contains, encrypted:

- **Saved places** — every city you've added, at the rounded precision you
  chose.
- **Settings** — units, location precision, and theme.

**The forecast cache is deliberately excluded.** It's disposable derived
data — raw Open-Meteo JSON, re-fetched automatically the next time you open a
saved place (see [`WeatherRepository`](../../lib/features/weather/data/weather_repository.dart)).
Backing it up would bloat every file with public weather data you never
chose, and a restored cache could already be stale the moment it lands.

## Setting up

1. Open **Settings → Backup → Set up encrypted backup**.
2. Write down the 12 recovery words on paper, then tap **I've written this
   down**. The words are stored on this device only at that tap; **Not now**
   stores nothing. **They are the only way to recover your data on a new
   device — WeatherGlass holds no copy, and there is no "forgot my words"
   recovery.**
3. Re-enter the 12 words, one at a time, to confirm you copied them
   correctly. This turns "I clicked OK" into a cryptographic proof the paper
   copy is right.

Until setup is finished, the top of Settings carries a one-line reminder with
**Set up** and **Dismiss** (a dismissal lasts 30 days). **Show my recovery
words** shows the stored words again, behind a confirm, if you need to check
or replace the paper copy.

## Exporting

**Settings → Backup → Export backup** encrypts everything above
into a `.ohbk` file and hands it to your device's share sheet — save it to a
file, email it to yourself, put it on a USB stick, whatever you trust. Nothing
is uploaded anywhere by WeatherGlass itself.

## Exporting as plain JSON (not encrypted)

**Settings → Backup → Export as plain JSON** hands the same saved places and
settings to the share sheet as a readable JSON file. It needs no recovery
words, and it is **not encrypted**: anyone who gets the file can read it. A
dialog says so before anything is shared, and the file name ends in
`-UNENCRYPTED.json`. Use it when you want to read your data in another
program. Restore takes a `.ohbk` file.

## Previous backups

**Settings → Backup → Previous backups** lists snapshots kept on this device.
An export leaves one, and a restore takes one of the current places and
settings first, so a mistaken restore can be undone from that list. You can
restore or pin a snapshot there. Snapshots stay on the device.

## Restoring

**Settings → Backup → Restore from backup**, then pick a `.ohbk`
file. Restoring is **destructive**: it replaces every saved place and every
setting on this device with what's in the file. You'll see a confirmation
dialog stating that plainly before anything happens — there is no partial or
silent restore.

If this device's key doesn't unlock the file (e.g. a fresh install, or a
backup made under different recovery words), you'll be asked to type the 12
words the backup was made with.

## The honest limits

- **Wrong words, no data.** There is no password reset. If the 12 words are
  lost, an existing `.ohbk` file cannot be decrypted by anyone, including us —
  that's the point of local-only key material, but it means the backup is
  only as safe as the paper it's written on.
- **A rejected restore never touches your data.** A backup from a different
  app, a newer schema than this version of WeatherGlass understands, or a
  corrupt file all fail before any write — you keep what you had.
- **Nothing of ours leaves the device.** Export writes bytes to the OS share
  sheet you choose; WeatherGlass runs no relay or server of its own. See
  [privacy-model.md](../privacy-model.md#what-stays-on-the-device) for the
  full accounting of what does and doesn't leave.
