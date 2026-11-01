# How to build & run Still Life

Goal: get from a fresh clone to the app running on a device or emulator.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel; the
  project targets Dart SDK `^3.10.7`).
- For Android: the Android SDK + a device or emulator.
- For iOS: Xcode (note iOS is not yet a shipped target — see
  [limitations](../limitations.md)).
- The sibling design-system package at `../ohStyle/openhearth_design`, which
  `pubspec.yaml` references by relative path. Check it out next to this repo.
- The sibling transfer/AI control plane at `../DomovoiDiscernment` (the
  `domovoi` package), likewise by relative path — it owns the resumable download
  engine the on-device model downloader runs on.

## Steps

```bash
# 1. Install Dart/Flutter dependencies
flutter pub get

# 2. Generate code — REQUIRED before the first run and after any schema/annotation change
dart run build_runner build --delete-conflicting-outputs

# 3. Run on a connected device or emulator
flutter run
```

Step 2 is not optional: the Drift database and its DAOs are code-generated. Skipping
it leaves `*.g.dart` missing and the build will fail. Re-run it whenever you edit
`lib/services/database/tables.dart`, `database.dart`, or any file with a
`@DriftDatabase` / `@DriftAccessor` annotation.

## Verify your change

```bash
flutter analyze     # lint — config in analysis_options.yaml (flutter_lints)
flutter test        # the full suite under test/; CI runs it with --coverage
```

Both must be green before you commit. To narrow the run:

```bash
flutter test test/unit test/widget          # skip the slower golden/visual tests
flutter test test/unit/services/sync        # one area
```

## Build artifacts

```bash
flutter build apk --debug     # Android debug APK (what CI builds for sanity)
flutter build linux           # desktop (builds in CI)
flutter build web             # web (builds in CI)
```

### The app's own address and the move page

Still Life on the web moves to its own address, `stilllife.familyflourishing.org`
(owner ruling, 15 Nov 2026), once that domain is live. `web/CNAME` names it,
and the build copies it to the site root. Two web builds then come from the
same code:

```bash
# The app at its own address
flutter build web --release --base-href /

# The move page, at levitatingflyfisher.github.io/move/stilllife/
flutter build web --release --base-href /move/stilllife/ --dart-define=OH_MOVE_PAGE=true
```

The move page stays up for good, because data saved at the old address can
only be read there. It opens straight to the move screen, counts the
records, saves the app's own backup file and writes nothing at start
(`lib/features/move/move_page.dart`). It goes in the landing repo under
`move/stilllife/`, without the `CNAME` file.

## The app has no configuration to run

Still Life starts into a working, empty catalogue with **no setup, no account, no
network**. Everything optional (AI analysis, barcode lookup, LAN sync, WebDAV backup)
is enabled later from **Settings**, and each is off until you turn it on.

## Note on CI

`.github/workflows/ci.yml` runs analyze → test → build (Android / Linux / Web) plus a
Node job for the `server/hosted-llm` worker. It triggers on pushes and pull
requests to `master`, the live branch.
