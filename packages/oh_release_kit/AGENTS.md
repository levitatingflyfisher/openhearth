# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

The map of `oh_release_kit`, the fleet's release checks. Read `README.md`
first: it says what each command checks and why.

## The map

| You're touching | Go to |
|---|---|
| The command line | `bin/release.dart` (one line), `lib/src/cli.dart` (reads files, prints, exit codes); `test/cli_test.dart` |
| What a check returns | `lib/src/check_result.dart` |
| `version` | `lib/src/version_check.dart`; `test/version_check_test.dart` |
| `shared-versions` | `lib/src/shared_versions.dart`; `test/shared_versions_test.dart` |
| `leakscan` | `lib/src/leakscan.dart`; `test/leakscan_test.dart` |
| `web-check` | `lib/src/web_check.dart`; `test/web_check_test.dart` |
| `apk-check` | `lib/src/apk_check.dart`; `test/apk_check_test.dart` |
| `export` | `lib/src/export.dart`; `test/export_test.dart` |

## Rules

- **Every rule is a pure function with tests.** `cli.dart` only reads files,
  runs tools and prints. A new check starts as a failing test.
- **Exit 1 is a failed check, exit 2 a command that could not run.** Never
  let a missing file or tool look like a pass.
- **No private word in this repo, not even in a test.** People's names,
  personal domains and family words live only in the `--private` patterns
  file outside the repo. Tests use made-up words like `examplename`.
- **Test fixtures that should trip the leak scan are built from split
  string literals**, so a scan of a diff that holds this package stays
  clean. The patterns in `leakscan.dart` are written the same way.
- **Pure Dart, few dependencies.** `path` and `yaml`, `test` and `lints`.
  No Flutter, no network. A new dependency must earn its place.
- **No build in the suite.** APK parsing is tested on canned tool output.
- **Scratch on real disk,** under `.dart_tool/kit_test_tmp/`.
- Commits are small and say why. No attribution lines.
