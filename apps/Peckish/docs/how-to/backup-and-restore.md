# Back up and restore

Settings → **Your data**.

**Encrypted backup (.ohbk)** — the sanctuary section walks you through a
household seed phrase once, then writes an encrypted `.ohbk` file you can
keep anywhere (drive, email to yourself, another phone). Restore picks a
file, previews what's inside (age, source app), states exactly what it will
replace, and only then writes. Restores are atomic: a failure partway leaves
current data untouched.

Android may also back up this app’s data to Google, if the phone’s owner
allows it in Android settings. The encrypted backup here is the private
choice. (The file that holds the sync secret, the stove phrase and the
Anthropic key is kept out of Android backup.)

**Plain export** — a readable JSON copy of everything (diary, foods, meals,
recipes, plan, groceries, targets, regulars). The file is the interface:
keep it, grep it, move it.

**Erase all data** — deletes the user tables, the unsaved recipe drafts,
the AI settings (with the AI key and the stove phrase), the household sync
code and the suggestion card's settings. It keeps only your theme, the
built-in food database, the offline barcode database and the downloaded AI
model. If backup is set up, a verified safety copy of your data goes into
Previous backups first, and the erase only happens once that copy is
proven readable; restoring it brings back your diary, foods, meals,
recipes, plan, groceries and targets. No backup carries the AI settings,
the sync code, the recipe drafts or the suggestion card's settings. If the copy fails, nothing is erased.
Without backup there is no copy, and the confirmation says so.

Both an erase and a restore end a pending Undo (it would write a deleted
row back) and reload every cached copy of stored data. Ending an Undo runs
its commit step, so no Undo in Peckish has one (a test holds this). A restore also
clears the recipe drafts, so an old edit cannot be saved over a restored
recipe.

The bundled USDA spine is never in a backup — it ships with every install.
