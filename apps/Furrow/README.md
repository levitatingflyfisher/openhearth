# Furrow

> **We are what we repeatedly do.** A calm, local-first daily-virtue & habit
> grid for one person — Benjamin Franklin's thirteen-virtues book of days,
> reimagined without streak-shaming or dark patterns.

Furrow is a small Flutter app for tracking the things you do on purpose, over
and over, until the groove is worn. A *furrow* is a plough-line deepened by each
repeated pass — the metaphor and the interface are the same thing. Every habit
is one row; every day is one cell; inking a cell blooms the furrow. Fill a week
and it reads as a line cut clean.

It runs entirely on your device. No account, no cloud of its own, no ads, no
tracking — the app sends nothing anywhere. (Android may also back up the app's
data to Google, if the phone's owner allows it in Android settings; the
encrypted backup in Settings is the private choice.) (See the [privacy model](docs/privacy-model.md);
the shipped Android build carries no `INTERNET` permission at all.)

## What it does

- **Three cadences on one grid.** A habit is a **tick** (done / not-done), a
  **count** (reach N per day — 8 glasses of water), or a **timer** (accumulate
  time — 30 minutes reading). All three live on the same seven-day row.
- **The Franklin thirteen.** An optional starter set of Benjamin Franklin's
  thirteen virtues in his own order, each with its precept, plus a quiet
  "virtue of the week" rotation. It plants this week's virtue first; the others
  wait, resting, for their week, as Franklin worked them.
- **Calm by design.** Streaks never turn red, reset silently, and never nag.
  Stats are raw counts, not shame-inducing percentages. There are no punitive
  notifications. See [ADR-0007](docs/adr/0007-no-dark-patterns.md).
- **Six gentle awards**, earned once and kept — a slow confetti and a quiet
  fact line, never an "Achievement Unlocked!" jingle.
- **Ghost mode is the whole product.** Zero identity, zero server contact.

## Try it

- **Web (PWA):** <https://levitatingflyfisher.github.io/Furrow/> — installable,
  works offline.
- **Android (APK):** sideload the build attached to the repo's release tag.

## Quickstart (development)

Furrow consumes its shared packages by **sibling path dependency** (the same
convention as `eloEngine`): the encrypted-backup pair and the fleet
conformance tests under `../packages/`, and the design package in `../ohStyle`.
`pubspec.yaml` lists them. Clone them next to Furrow so the paths resolve:

```
packages/
  sanctuary_auth_core/     # github: levitatingflyfisher/sanctuaryAuthCore
  sanctuary_backup_ui/     # github: levitatingflyfisher/sanctuaryBackupUi
  oh_fleet_conformance/    # github: levitatingflyfisher/ohFleetConformance
ohStyle/                   # github: levitatingflyfisher/ohStyle
Furrow/                    # this repo
```

```bash
git clone https://github.com/levitatingflyfisher/sanctuaryAuthCore packages/sanctuary_auth_core
git clone https://github.com/levitatingflyfisher/sanctuaryBackupUi packages/sanctuary_backup_ui
git clone https://github.com/levitatingflyfisher/ohFleetConformance packages/oh_fleet_conformance
git clone https://github.com/levitatingflyfisher/ohStyle ohStyle
git clone git@github.com:levitatingflyfisher/Furrow.git
cd Furrow
flutter pub get

# Riverpod generates *.g.dart and Drift *.drift.dart files (gitignored) — run after every
# fresh checkout or dependency change, or the build fails on missing imports:
dart run build_runner build --delete-conflicting-outputs

flutter run           # launch on a device / emulator / web
flutter test          # unit, widget, and golden suites
flutter analyze       # static analysis — must be clean
```

Details in [docs/how-to/build-and-run.md](docs/how-to/build-and-run.md); the
PWA + APK release flow in [docs/how-to/ship-pwa-and-apk.md](docs/how-to/ship-pwa-and-apk.md).

## See the docs

Start with the **[Vision](VISION.md)** — the one idea, the design commitments,
and an honest scorecard of what's built versus aspirational. Then the
**[documentation index](docs/README.md)**, organized [Diátaxis](https://diataxis.fr/)-style
(tutorials · how-to · reference · explanation).

Working *in* the code (human or agent)? Read **[AGENTS.md](AGENTS.md)** first.

## Stack

Flutter, Clean Architecture (domain / data / presentation per feature),
[Riverpod](https://riverpod.dev/) for state, [Drift](https://drift.simonbinder.eu/)
over SQLite for local storage, `go_router` for navigation. Ships as both a PWA
and an Android APK from one codebase. The *why* behind each choice lives in
[docs/adr/](docs/adr/).

## License

[MIT](LICENSE). Lora and Nunito, bundled via ohStyle's `openhearth_design`
package, are licensed separately under the SIL Open Font License 1.1 (see
that package's `fonts/OFL.txt`).
