# oh-packages

The shared Dart packages of the OpenHearth fleet, in one repo.

| Folder | What it is |
|---|---|
| `sanctuary_auth_core/` | The crypto core: recovery words, keys, secure storage and the sync client. |
| `sanctuary_backup_ui/` | The backup and restore screens every app shares, built on `sanctuary_auth_core`. |
| `oh_fleet_conformance/` | A test package that checks an app against the fleet's standards. Apps list it under `dev_dependencies`. |
| `oh_release_kit/` | The release checks as one command-line tool: version, shared package versions, leak scan, web build, APK and clean export. Pure Dart; apps do not depend on it. |

## How apps use them

This repo is checked out as `packages/`, beside the apps. Each app depends on a
package by path:

```yaml
dependencies:
  sanctuary_auth_core:
    path: ../packages/sanctuary_auth_core
```

`sanctuary_backup_ui` reaches `sanctuary_auth_core` the same way, through
`../sanctuary_auth_core`.

## Working here

Each folder is a whole package with its own `pubspec.yaml`, tests and docs.
Run `flutter pub get` and `flutter test` inside the folder you change;
`oh_release_kit` is pure Dart, so there it is `dart pub get` and `dart test`.
Each package came from its own repo; its full history is kept here.
