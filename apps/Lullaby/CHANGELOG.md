# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- The encrypted backup now carries the baby's photo itself, not only its
  path, so a restore on a new phone brings the photo back. A photo up to
  1 MiB goes in as it is; a larger one as a 512-pixel copy. Settings says
  the photo is in the encrypted backup.
- Sync with another phone, off by default: two parents keep one record,
  with changes sealed under the household's 12 recovery words. Phone to
  phone on the same Wi-Fi with a code (Android app only), or through a
  relay the household chooses. Edits to different fields of one record
  both survive, deletes keep a lasting Undo, and "Forget this phone"
  removes a lost phone. The app now asks for one Android permission,
  `INTERNET`, used only once sync is on (ADR-0007).
- Note for the next shift: a line one parent leaves the other, on Home.
  It syncs to the other phone and is kept in backups.
- Deleting a record from its edit form happens at once and offers an Undo
  bar that stays until you act on it; it survives the form closing.
  Swiping a growth, medicine or vaccine row away asks first, with a
  button that names what goes.
- Theme toggle in the top bar (Follow phone / Light / Dark), two taps
  from every tab, remembered across launches.
- A dismissible "finish setup" line at the top of Settings while encrypted
  backup is not set up.
- Fleet checks C9 (every route has a door), C10 (no raw error text), C11
  (top-bar actions carry words), C12 (accent is not the error red) and the
  360dp x 1.3 primary-action sweep.
- Fleet conformance suite (`oh_fleet_conformance` dev dependency +
  `test/fleet_conformance_test.dart`): Lullaby's recorded posture is
  tokens-tier style, one Android permission in the source manifest
  (`INTERNET`, added for opt-in sync; the set is an enforced claim, both
  directions), backup on the shared retention package, and size budgets. `budgets.json` records the baselines
  (gzipped `main.dart.js` + arm64 release APK, +5%) so size regressions
  fail the suite on any machine that has built the artifacts — the
  ratchet bites on local and deploy builds. (CI builds the web bundle,
  so the JS budget is checked there. CI builds no APK, so the APK budget
  is checked only on a machine that has built one.)
- CI clones the `ohStyle` and `ohFleetConformance` sibling repos so the
  workflow covers every path dependency the pubspec declares.

### Changed
- Built on Riverpod 3. Nothing a parent sees changes: a failed read still
  says so once, with Try again, and is not reloaded in a loop; a running
  timer still follows a switch of baby; a restore still brings back only the
  restored record's timers.
- Text is set in the fleet's type (ohStyle's Lora and Nunito, bundled, on
  the shared type ladder) instead of the platform font; C7 now guards the
  glyphs.
- The running-timer card stacks its label, clock and STOP when they do
  not fit on one row, so the clock never breaks a digit per line.
- Tabs grow with the text size, so their labels are no longer cropped.
- The stored theme is read before the first frame, so a Dark choice does
  not flash light at launch.
- A screen that fails to load says what did not load and offers Try again,
  instead of printing the exception.
- Content is capped at 640dp and centred on tablets and in the browser
  (OhPage); app bars span the window. This replaces the fixed 760px box
  around the whole app.
- Top-bar actions are icon plus word: Settings, Edit, Delete.
- The growth chart spaces its axis labels by their measured size and
  prints the unit once, so labels no longer overlap at large text.
- The Home summary labels wrap onto a second line instead of being cut
  off inside a chip at large text.
- Calendar opens from the top of Timeline → Events, so the Timeline title
  stays whole at large text.
- First run scrolls, so Add Baby stays reachable at large text.
- On web, recovery words are kept under Lullaby's own names rather than
  shared with other fleet apps in the same browser.
- Category colours live in one table; the sleep chart uses the sleep colour.
- `test/flutter_test_config.dart` re-synced to the fleet-canonical
  variant: per-family font-load isolation (one font family failing to
  load no longer aborts the families after it). The success path is
  identical — all goldens verified byte-identical.
- `test/flutter_test_config.dart` replaced with the fleet-canonical
  FontManifest-aware variant (byte-identical across Trellis/Reckon/
  StillLife). All goldens re-rendered byte-identically — Lullaby bundles
  no custom text fonts, so nothing visual changed.
- Depend on the shared `openhearth_design` package (path dep, v0.4.0) as
  conformance readiness. A sweep of `lib/` found ZERO literals equal to
  canonical OpenHearth token values, so no colors were rewired and nothing
  visual changed; a readiness test pins the canonical token values and
  proves Lullaby's signature periwinkle (`0xFF7B8FD4`) is app-local
  identity, not a canonical token. Lullaby's type ladder and its
  Material-You dynamic-color hook remain untouched by design.
- Snapshot vault ("Previous backups"): every export and every restore now
  leaves a stamped on-device snapshot (keep-10, pinnable) you can restore,
  pin or delete from Settings.
- Mandatory pre-restore snapshot: a restore refuses to run unless the
  current data was snapshotted first — restoring is now reversible.
- Preview before restore: the confirm dialog shows the backup's age and
  per-table row counts next to what's on the device now.
- Every export verifies itself by read-back before reporting success.
- Plain-JSON export (unencrypted, honestly labeled) from Settings.
- Silent freshness snapshot when the newest one is older than 7 days.

### Fixed
- The home-screen widget showed the first "last sleep" and "last diaper"
  it read for as long as the app ran: a new sleep or diaper, or a restore,
  did not reach it. After a restore it could also show the old baby's name
  and last feed. It now reads the database on every redraw.
- The growth screen's "Latest Measurement" card kept the first
  measurement it showed, through new measurements and restores. It now
  follows the database.
- After a restore, a sleep or feed still running in the restored record
  shows its timer again, in the app and on the widget.
- Doctor summary: a baby with no recorded sex now gets the honest WHO
  notes it was promised. The out-of-range note (measurement beyond the
  0–24 month tables) no longer depends on a recorded sex, and when the
  measurement IS in range a new note names the actual blocker —
  "WHO percentiles need a recorded sex" — on screen and in the PDF
  export, instead of silently omitting percentiles.
- WHO percentile interpolation returns the documented null instead of
  crashing when handed a band map missing a canonical band (3/15/50/
  85/97).
- Fresh-install restore with recovery words now adopts those words as the
  device identity — previously the restored data was orphaned and a new
  export required minting a new identity that didn't match the user's
  written-down phrase.
- Web (PWA): baby photos and data exports no longer crash. Five UI files
  bare-imported `dart:io`, which compiles on web but throws at runtime —
  avatars broke as soon as a baby had a photo set, and every export tap
  crashed. Photos now resolve through a platform trio (initial-letter
  avatar + honest "photos are available in the Android app" copy on web);
  CSV/PDF exports share bytes via the Web Share API with a plain-download
  fallback, so they genuinely work in every browser. A suite-level guard
  now fails CI if a bare `dart:io` import ever reappears in shared code.
- WHO growth percentiles are honest at the edges: a measurement outside
  the 0–24-month tables now shows a calm "outside that range" note
  (screen + PDF) instead of silently scoring against the 24-month curves;
  a measurement matching no band (e.g. NaN) no longer reports a fabricated
  50th percentile; degenerate equal-band interpolation can no longer
  produce NaN. In-range math is regression-locked byte-identical.

---

## [1.0.0] - 2026-02-24

### Added

**Tracking**
- Feeding log with breast, bottle, and solid feed types; left/right side toggle; live elapsed timer
- Sleep log with start/stop timer and duration history
- Diaper log with wet, dirty, and mixed change types
- Quick-log buttons on the dashboard for one-tap entry
- Active timer card on the dashboard showing an in-progress session

**Growth**
- Weight, height, and head circumference measurements
- Growth curves chart plotting measurements against WHO percentile data (boys and girls)

**Health**
- Medicine dose log (name, dose, unit, time)
- Vaccination history with date and vaccine name

**Statistics**
- Feeding trend chart (volume / session count over time)
- Sleep pattern chart (total sleep per day)
- Diaper frequency chart
- Configurable time period selector (7 days, 14 days, 30 days)

**Calendar**
- Monthly calendar view with event markers per day
- Day event sheet listing all activity for a selected date

**Timeline**
- Scrollable reverse-chronological activity feed
- Filter chips for feeding, sleep, diaper, growth, medicine, and vaccine events

**Dashboard**
- Daily summary strip (feed count, sleep total, diaper count)
- Recent activity list

**Baby profiles**
- Name, date of birth, and avatar photo
- Multiple baby support with a switcher sheet
- Age display (newborn / days / months / years)

**Doctor summary**
- At-a-glance summary of recent activity, growth measurements, and upcoming vaccinations

**Settings**
- Theme mode selector (system / light / dark)

**Architecture & Infrastructure**
- Clean architecture with feature-based folder structure
- Riverpod 2.x state management throughout
- Drift ORM on SQLite for local, offline-first data persistence
- go_router navigation with tab shell and modal routes
- Material 3 dynamic colour theming (Android 12+)
- 326 unit and widget tests; zero static analysis issues
- Android, iOS, and Linux platform support
