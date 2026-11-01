# Changelog

All notable changes to porch. The newest come first. A heading names the version once it is released.

## [Unreleased]

Since the October 2026 preview.

### Safety of your identity and keys

- Settings has “Start over with a new identity”, for when your words or a backup file may have leaked. Porch leaves every group first, then forgets the identity and the backup files on this phone. If a group can’t be reached, it says which one and waits for your choice.

- A stored identity or state key that can’t be read is now shown as an error. Before, porch treated it as missing, and could start over or write a new identity over the old one.
- When the stored identity can’t be read, porch offers to restore from your 12 words or a backup. The unreadable copy is first set aside under a dated name, so nothing is lost for good.
- A phone keystore that refuses at launch is shown with Try again, and so is any failure while porch starts.
- The identity and the state key are kept out of Android’s backup to Google and out of device transfer. Android’s own backup stays the phone owner’s choice, and Settings says so.
- A backup file is no longer locked by a PIN you pick. Porch picks 6 backup words for you and shows them beside your 12 words; they unlock the file. A 4-digit PIN could be guessed in hours.
- On iPhone and Mac, the identity and the state key stay in this device’s keychain and never travel in iCloud or computer backups.
- Backup files stay out of Android’s backup to Google and out of iCloud. They leave the phone only when you share one.
- On iPhone and Mac, backup files now live where the system never clears them to free space, in a folder marked to stay out of iCloud and computer backups.
- A backup file that asks for an absurd amount of memory or work is refused before porch tries to open it.
- The note beside your 6 backup words says what they open: nothing alone, but with any backup file your identity and every group. They can’t be changed, so keep them apart from your backup files.

### The relay

- Porch talks to a relay over https only. Settings refuses a plain http address and says why. A developer build may still use http to a relay on the same machine.
- A full relay now says so (507) and never drops stored data to make room. Your app keeps what it was sending and tries again.
- One address may open only 50 mailboxes and channels a day, so one person can no longer fill the relay and stop new groups from starting.

### On the web

- The web page now runs only porch’s own script files, under a Content-Security-Policy.
- One line above every screen says your data lives in this browser, and that clearing the browser’s website data erases it. The red Web preview banner about keys stays.

### Other

- Settings names the publisher, Intergenerational Symbolic Systems.
- The donation link is gone.
- A failed read of your identity or state shows a plain sentence and Try again, never a blank screen.
