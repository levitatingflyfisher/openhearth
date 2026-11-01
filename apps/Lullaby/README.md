# Lullaby

**FLOSS baby tracker for exhausted parents.**

Lullaby is a privacy-first, offline baby tracking app. All data is stored locally on the device — no accounts, no ads, no tracking. Two parents can opt in to syncing one record between their phones, sealed with their recovery words. Track feeds, sleep, diapers, growth, health records, and more, all in one place.

![Platform: Android](https://img.shields.io/badge/platform-Android-brightgreen)
![Platform: iOS](https://img.shields.io/badge/platform-iOS-lightgrey)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

> **Vision.** A newborn generates a river of intimate medical data — when they
> ate, how they slept, every medicine and vaccine. That record should live on
> *your* phone and nowhere else. Lullaby is the calm, private, no-account
> alternative to cloud baby trackers: your child's data never leaves the device
> unless you deliberately export it, or turn on sync with your partner's
> phone (sealed end to end; the relay cannot read it). On Android, the phone's
> owner may also let Android back the app up to Google in Android settings; the
> key store with the recovery words is left out of that backup, and the
> encrypted backup is the private choice.

**New here?** Read the [Vision](VISION.md) for the one idea and the honest
scorecard, then browse the [documentation](docs/README.md) (organized
[Diátaxis](https://diataxis.fr/)-style). Contributing or using an AI agent in
this repo? Start with [AGENTS.md](AGENTS.md).

---

## Features

- **Feeding tracker** — log breast, bottle, and solid feeds; left/right side toggle with live timer
- **Sleep tracker** — start/stop sleep sessions with a live timer; view sleep history
- **Diaper tracker** — log wet, dirty, and mixed changes
- **Growth charts** — record weight, height, and head circumference plotted against WHO percentile curves
- **Health records** — medicine dose log and vaccination history
- **Statistics** — feeding trends, sleep patterns, and diaper frequency charts over configurable periods
- **Calendar view** — browse all events by day
- **Timeline** — scrollable activity history with filter chips
- **Doctor summary** — at-a-glance summary ready to share at appointments
- **Multiple babies** — manage profiles for more than one child
- **Home-screen widget** (Android): the baby's name, the last feed, sleep and diaper, and a running timer, at a glance
- **Note for the next shift** — a line one parent leaves the other, on Home
- **Sync with another phone** (opt-in) — two parents, one record: changes travel sealed with your 12 recovery words, straight to the other phone on the same Wi-Fi (one shows a code, the other types it; no server at all, Android app only) or through a household relay; edits to different fields of one record both survive, deletes keep a lasting Undo, and a lost phone is removed with "Forget this phone". The second phone joins by typing the same words.
- **Dark mode** — follow the phone, or choose Light or Dark from the top bar; the choice is remembered
- **Material 3** — dynamic colour theming on supported Android devices

---

## Screenshots

*Screenshots coming soon.*

---

## Tech Stack

| Layer | Library |
|-------|---------|
| UI framework | [Flutter](https://flutter.dev) (a release that bundles Dart ≥ 3.10.7) |
| State management | [Riverpod](https://riverpod.dev) 2.x |
| Database | [Drift](https://drift.simonbinder.eu) (SQLite ORM) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| Charts | [fl_chart](https://pub.dev/packages/fl_chart) |
| Calendar | [table_calendar](https://pub.dev/packages/table_calendar) |
| Dynamic colour | [dynamic_color](https://pub.dev/packages/dynamic_color) |
| Image picker | [image_picker](https://pub.dev/packages/image_picker) |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install), a release that bundles Dart ≥ 3.10.7 (CI pins Flutter 3.38.7)
- Dart SDK ≥ 3.10.7 (bundled with Flutter)
- For Android: Android SDK / Android Studio
- For iOS: Xcode ≥ 15 (macOS only)
- For Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

### Setup

Lullaby consumes its shared code by **sibling path dependency**: the two
encrypted-backup packages and the fleet's conformance checks under
`../packages/`, the design package in `../ohStyle`, and the sync kernel in
`../hearthSync`. Clone them next to Lullaby so the paths in `pubspec.yaml`
resolve:

```
packages/
  sanctuary_auth_core/     # github: levitatingflyfisher/sanctuaryAuthCore
  sanctuary_backup_ui/     # github: levitatingflyfisher/sanctuaryBackupUi
  oh_fleet_conformance/    # github: levitatingflyfisher/ohFleetConformance (dev dependency)
ohStyle/                   # github: levitatingflyfisher/ohStyle (design package)
hearthSync/                # github: levitatingflyfisher/hearthSync (sync kernel)
Lullaby/                   # this repo
```

Two-phone sync uses the fleet's sync kernel, `hearth_sync`, by the same kind
of sibling path (`../hearthSync/flutter/hearth_sync`). Its Rust kernel is
built for Android by the plugin's own Gradle step (cargokit); the web build
needs the kernel's WASM in `web/pkg/` (`tool/build_web.sh` makes it).

```bash
git clone https://github.com/levitatingflyfisher/sanctuaryAuthCore packages/sanctuary_auth_core
git clone https://github.com/levitatingflyfisher/sanctuaryBackupUi packages/sanctuary_backup_ui
git clone https://github.com/levitatingflyfisher/ohFleetConformance packages/oh_fleet_conformance
git clone https://github.com/levitatingflyfisher/ohStyle ohStyle
git clone https://github.com/levitatingflyfisher/hearthSync hearthSync
git clone <repo-url> Lullaby
cd Lullaby
flutter pub get
```

### Run in debug mode

```bash
# List connected devices/emulators
flutter devices

# Run on a specific device
flutter run -d <device-id>
```

---

## Building

### Android

```bash
flutter build apk --release
# or for an app bundle:
flutter build appbundle --release
```

> **Note:** The Android `applicationId` is `com.openhearth.lullaby`, and the release build is signed with the debug key. Before publishing to an app store, configure a release signing key in `android/app/build.gradle.kts`.

### iOS

```bash
flutter build ios --release
```

Requires a valid Apple developer signing certificate configured in Xcode.

### Linux

```bash
flutter build linux --release
```

The resulting binary is at `build/linux/x64/release/bundle/lullaby`.

---

## Architecture

Lullaby follows **clean architecture** with a **feature-based folder structure**:

```
lib/
├── app/              # App entry, router, theme
├── core/             # Shared utilities, errors, extensions, providers
├── features/         # One sub-directory per feature
│   ├── babies/       # Baby profiles
│   ├── tracking/     # Feeding / sleep / diaper tracking
│   ├── growth/       # Growth measurements & WHO charts
│   ├── health/       # Medicine & vaccine logs
│   ├── stats/        # Aggregated statistics
│   ├── calendar/     # Calendar view
│   ├── timeline/     # Activity timeline
│   ├── dashboard/    # Home dashboard
│   ├── doctor/       # Doctor summary
│   ├── export/       # CSV / PDF export
│   ├── handoff/      # Note for the next shift
│   ├── home_widget/  # Android home-screen widget
│   ├── sanctuary_backup/  # Encrypted backup / restore
│   ├── sync/         # Two-phone sync
│   └── settings/     # App settings
│
│   Most features contain:
│   ├── domain/       # Entities & repository interfaces
│   ├── data/         # Repository implementations (Drift DAOs)
│   └── presentation/ # Screens, widgets, Riverpod controllers
│
└── services/
    └── database/     # Drift database definition, tables, DAOs
```

State is managed exclusively with **Riverpod** providers. The database layer uses **Drift** with generated code (`*.g.dart` files).

---

## Tests

```bash
# Run all tests
flutter test

# Static analysis
flutter analyze
```

The test suite covers domain entities, repository implementations (using an in-memory SQLite database), controllers, widgets, and golden (visual) tests. CI runs `flutter analyze`, a web release build and `flutter test` on every push to `master` and every pull request (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

---

## License

MIT — see [LICENSE](LICENSE).

---

## About

Lullaby is part of **OpenHearth** — a family of free, local-first, open-source
tools for households. The shared ethos: your data stays on your device, there
are no ads or tracking, and no account is required to use the app. See the
[Vision](VISION.md) for what that means here.
