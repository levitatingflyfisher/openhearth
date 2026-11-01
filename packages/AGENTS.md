# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

The map of the shared OpenHearth packages. Read `README.md` first.

## The map

- `sanctuary_auth_core/`: the crypto core. Its own `AGENTS.md` and `VISION.md` hold its rules.
- `sanctuary_backup_ui/`: the shared backup and restore screens. Its own `AGENTS.md`,
  `VISION.md` and `docs/adr/` hold its rules and decisions.
- `oh_fleet_conformance/`: the fleet's standards as tests.
- `oh_release_kit/`: the release checks as one command-line tool. Pure Dart, so its
  suite is `dart test`. Its own `AGENTS.md` holds its rules.

## How to work

- Every fleet app depends on these by path, `../packages/<name>`. A change here reaches
  every app at its next `pub get`. A breaking change names the apps it breaks in its
  commit message and in the package's `CHANGELOG.md`.
- Run the suite of each package you touch, inside its folder: `flutter test`
  (`dart test` for `oh_release_kit`).
- Build output (`build/`, `.dart_tool/`, `coverage/`) is never committed.
