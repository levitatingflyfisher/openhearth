# Back up and restore progress

Hatch's data — every profile, its answer history, and its engine state —
lives on your device, and the app sends it nowhere. The backup is a single
encrypted `.ohbk` file that you keep wherever you keep files. Android may
also back up the app's data to Google, if the phone's owner allows it in
Android settings. The encrypted backup here is the private choice.

## Back up

1. Open **Settings** (from the profile picker or home).
2. The first time, in the **Encrypted Backup** section, choose **Set up
   encrypted backup**. The app shows 12 recovery words. Write them down and
   type them back in when asked. **Export backup** appears only after that.
3. Choose **Export backup**.
4. The system share sheet opens with the `.ohbk` file. Send it wherever the
   share sheet reaches (your files app, a USB drive, a family NAS).

Keep the 12 words with the file. A device that does not already hold them
asks for them before it can open the backup.

The file is encrypted with the fleet's shared backup format (ChaCha20-
Poly1305 under an app-scoped key; a Hatch backup cannot be restored into a
different OpenHearth app, and vice versa). One file carries **all** profiles
on the device.

## Restore

1. On the new device (or fresh install), open **Settings** — reachable
   before any profile exists, precisely for this moment.
2. **Restore from backup**, pick your `.ohbk` file, and enter the 12
   recovery words if the app asks for them.
3. Read the confirmation carefully: restore **replaces** everything currently
   in the app with the backup's contents. It says so before it does it.
4. The app returns to the profile picker; every hatched critter, every
   scheduled review, and the calendar spacing history arrive intact —
   reviews that came due while the backup sat in a drawer are simply waiting,
   never penalized.

## A plain copy, not encrypted

The same section has **Export as plain JSON**. It hands the share sheet a
file that any program can read, with no recovery words needed. It holds
everything the backup holds, including each profile's name and answer
history, so anyone who gets the file can read it. The app asks before it
makes one. It is a copy to read; restore is for `.ohbk` files.

## Moving between devices

Export on the old device, move the file however you like (the app itself
never touches a network), restore on the new one. That's the whole story.
