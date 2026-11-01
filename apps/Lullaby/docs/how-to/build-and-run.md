# How to build & run Lullaby

Task-oriented setup for developers. Assumes you can use a terminal and have (or
can install) Flutter. For the architecture, see
[../architecture/OVERVIEW.md](../architecture/OVERVIEW.md).

## Prerequisites

- **A Flutter SDK that bundles Dart ≥ 3.10.7.** Verify with `flutter --version`.
  CI pins Flutter `3.38.7`; older releases shipped a Dart too old to satisfy the
  pubspec constraint.
- **Android:** Android Studio / Android SDK.
- **iOS:** Xcode ≥ 15 (macOS only).
- **Linux desktop:** `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`.

## Get the code and dependencies

```bash
git clone git@github.com:levitatingflyfisher/Lullaby.git
cd Lullaby
flutter pub get
```

`flutter pub get` resolves everything only when the sibling checkouts that
`pubspec.yaml` names by path are in place: `../packages/sanctuary_auth_core`,
`../packages/sanctuary_backup_ui`, `../packages/oh_fleet_conformance`,
`../ohStyle` and `../hearthSync`. CI clones them from their own public repos
alongside this one. A fresh local checkout needs the same siblings cloned next
to `Lullaby/` at the same directory level; the README's Setup section has the
commands (see also [../reference/backup-format.md](../reference/backup-format.md)).

## Generate database code (only after changing the schema)

The Drift-generated files (`*.g.dart`) are committed, so a fresh checkout needs no
codegen. Re-run it whenever you edit `lib/services/database/tables.dart` or a
DAO's queries:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Never hand-edit the generated `*.g.dart` files.

## Run

```bash
flutter devices                 # list emulators / connected devices
flutter run -d <device-id>      # run in debug
```

## Verify your setup

```bash
flutter analyze                 # must be clean
flutter test                    # the suite under test/; must be green
```

## Build a release artifact

```bash
# Android
flutter build apk --release
flutter build appbundle --release

# iOS (requires Apple signing configured in Xcode)
flutter build ios --release

# Linux desktop  → build/linux/x64/release/bundle/lullaby
flutter build linux --release

# Web  (ships sqlite3.wasm + drift_worker.js from web/ — keep them in sync with the drift version)
flutter build web --release
```

> The Android `applicationId` is `com.openhearth.lullaby`, and the release
> build is signed with the debug key. Before publishing to an app store,
> configure a release signing key. There is no release workflow yet; the only
> workflow is `.github/workflows/ci.yml`.

### The app's own address and the move page

Lullaby on the web moves to its own address, `lullaby.familyflourishing.org`
(owner ruling, 15 Nov 2026), once that domain is live. `web/CNAME` names it,
and the build copies it to the site root. Two web builds then come from the
same code, both through `tool/build_web.sh` so the sync kernel's WASM is
beside them:

```bash
# The app at its own address
tool/build_web.sh --base-href /

# The move page, at levitatingflyfisher.github.io/move/lullaby/
tool/build_web.sh --base-href /move/lullaby/ --dart-define=OH_MOVE_PAGE=true
```

The move page stays up for good, because data saved at the old address can
only be read there. It opens straight to the move screen, counts the
records, saves the app's own backup file and writes nothing at start
(`lib/features/move/move_page.dart`). It goes in the landing repo under
`move/lullaby/`, without the `CNAME` file.

## Troubleshooting

- **Version-solving fails on `sdk`/Dart version:** your Flutter is too old — its
  bundled Dart is below 3.10.7. Upgrade Flutter (CI uses 3.38.7).
- **Build errors mentioning `*.g.dart` / missing Drift types:** re-run
  `build_runner` (above).
- **Web build runs but the DB doesn't load:** confirm `web/sqlite3.wasm` and
  `web/drift_worker.js` are present and match your `drift` version.
