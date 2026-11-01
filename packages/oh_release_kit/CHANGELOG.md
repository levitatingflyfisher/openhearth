# Changelog

## 0.1.0

First release: one release kit for every fleet app, with the app's folder
as the argument.

- `version`: version and build agree in `pubspec.yaml`, the version
  constant, `CHANGELOG.md` and the fastlane changelogs.
- `shared-versions`: every path package from `pubspec.lock`, with version,
  path and commit, for the release ledger.
- `leakscan`: the generic checks in code; private words only from a
  `--private` patterns file kept outside the repo. `--all-lines` for commit
  messages.
- `web-check`: base href, manifest, gzip size budget, no CDN or font host,
  self-hosted CanvasKit and fonts.
- `apk-check`: package name, version code, version name and size budget
  from `aapt2`; sha256 and signer from `apksigner`.
- `export`: `git archive` of the release commit into a new folder on real
  disk.
