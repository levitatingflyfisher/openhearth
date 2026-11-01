# Contributing to Reckon

Thank you for taking the time to contribute! This document explains how to report issues, suggest features, and submit code changes.

---

## Reporting Bugs

Before opening a new issue, search existing issues to avoid duplicates.

When filing a bug report, please include:
- Flutter version (`flutter --version`)
- Device/OS and version
- Steps to reproduce
- Expected behaviour vs. actual behaviour
- Any relevant log output (`flutter logs`)

---

## Suggesting Features

Open an issue with the `enhancement` label. Describe the problem you are trying to solve rather than jumping straight to a solution — this helps discussion stay focused.

---

## Development Setup

```bash
git clone <repo-url>
cd reckon
flutter pub get
```

Reckon runs a small on-device model for the decision interview, the outside view and the reveal. No cloud API key is required, and the app runs offline once a model is downloaded. `flutter pub get` needs the sibling checkouts listed in the project README.

To regenerate Drift database code after changing table definitions:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Code Style

All contributions must pass the following checks before review:

```bash
# Format
dart format .

# Static analysis (must have zero issues)
flutter analyze

# Tests (must all pass)
flutter test
```

The project uses `package:flutter_lints` with standard rules — no overrides. Do not disable lint rules without a well-reasoned justification in the PR description.

---

## Testing

- Every new feature must include tests.
- Bug fixes should include a regression test where feasible.
- Tests live in `test/` and mirror the `lib/` structure (`test/app/`, `test/core/`, `test/features/`, `test/shared/`). Golden tests are in `test/visual/` and the screen-size sweeps in `test/a11y/`.
- Repository tests use an in-memory SQLite database (no mocking needed thanks to Drift's `NativeDatabase.memory()`).

---

## Pull Request Workflow

1. Fork the repository and create a feature branch from `master`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. Make your changes, following the code style rules above.
3. Open a PR against the `master` branch with a clear description of what changed and why.
4. Link any related issues in the PR description (`Closes #123`).

PRs that fail `flutter analyze` or `flutter test` will not be merged.

---

## Architecture Notes

Reckon uses clean architecture with a feature-based folder layout. When adding a new feature:

1. Create a directory under `lib/features/<feature-name>/` with three sub-directories:
   - `domain/` — define entity classes and an abstract repository interface
   - `data/` — implement the repository over the Drift database, with its Riverpod providers beside it
   - `presentation/` — screens, widgets, and Riverpod controllers/providers

2. Add each database table as its own file under `lib/core/database/tables/` and register it in `lib/core/database/app_database.dart`.

3. Run `dart run build_runner build --delete-conflicting-outputs` to regenerate Drift code.

4. Declare the new repository provider in the feature's `data/` folder (see `lib/features/case/data/case_providers.dart`).

5. Add routes in `lib/app/router.dart`.

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

For questions, open an issue on GitHub.
