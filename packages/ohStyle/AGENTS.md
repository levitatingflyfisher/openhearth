# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

Guidance for AI coding agents (and humans) working in this repo. This is the
top-level map. Read it before non-trivial work.

**Read these three, in order, before you change a token, a theme or a shared widget:**
1. [VISION.md](VISION.md): what must stay true and why (the invariants), and the honest scorecard.
2. [README.md](README.md): how an app uses the package, with examples for every widget.
3. [openHearthStyleGuide.md](openHearthStyleGuide.md): the design rules and the reasons for them.

## Take the code as a record of what exists

Every line of source, every comment and every doc here was written by an AI
assistant. Treat it as **an accurate record of what currently exists, offered
with gratitude and a grain of salt.** It is not a specification and it is not
guaranteed correct. A comment that claims an invariant is a hypothesis to verify.
When they disagree, the order of authority is: reality, then tests, then code,
then comments, then prose docs. (Two live examples: section 10 of the style
guide describes a `components/` folder and an icon package that were never
built, and several code comments point to a `CLAUDE.md` that is not in the repo.
Confirm before you rely.)

## What this is

The shared design package of the OpenHearth fleet of household apps.
`openhearth_design` is a Flutter package: colour, type, spacing, three themes, bundled fonts and a few shared widgets.
`openhearth_tokens` is two hand-kept files, `tokens.css` and `tokens.ts`, with the same values for projects that do not use Flutter.

## Non-negotiables (breaking one is a regression)

- **Contrast holds in all three themes.** Text clears 4.5:1 and marks clear 3:1
  on every ground. If you change a colour or wire a new theme slot, add the pair
  to `openhearth_design/test/contrast_test.dart`. Do not lower a floor to make a
  colour fit.
- **All three themes go through one builder.** `light()`, `hearthDark()` and
  `night()` share `_baseTheme` in `openhearth_design/lib/src/theme.dart`. A new
  slot is a new parameter there, set for all three.
- **Warmth is never used for an error or a destructive act,** and urgency never
  rests on colour alone: it carries an icon and a word. Plain icons stay neutral.
- **Fonts come from `openhearth_design/fonts/` and nothing is fetched.** No
  `google_fonts`, no font from a network. Do not ask for a weight or style that
  has no file: there is no Lora 300 or 600 and no Nunito italic.
  `test/font_bundle_test.dart` fails if a style does.
- **Every text size is on `OhTypography.ladder`.** Do not add a size between two
  steps.
- **A raw exception is never shown as the main text.** Use `OhErrorState` or
  `ohFriendlyErrorMessage`.
- **Undo has no timer.** Do not add one to `OhUndoController` or `OhUndoBar`.
- **No new runtime dependency.** The package depends on the Flutter SDK alone.
  Every consuming app inherits whatever is added here.
- **The package must compile without `dart:io`.** Keep io types behind the
  conditional import in `lib/src/errors/`.
- **A token value changes in all four places, in one piece of work:** the style
  guide, `openhearth_design/lib/src/colors.dart` (or the matching Dart file),
  `openhearth_tokens/tokens.css` and `openhearth_tokens/tokens.ts`. Only the Dart
  file is under test, so the other three are on you. Two other repos keep their
  own older copies of the CSS file. A change here does not reach them.
- **A change that alters how apps render is written in
  `openhearth_design/CHANGELOG.md`,** with the old and new values and the work
  each app has to do, and the version in `pubspec.yaml` moves with it.
- **Tests first.** Every new token or widget ships with a test. Every bug fix
  ships with a test that fails without the fix.
- **Atomic commits, one concern each.** The message states the why. No
  authorship or tool attribution lines in a commit.
- **Never commit** `CLAUDE.md`, `GEMINI.md` or `docs/superpowers/`. They are
  local working files and `.gitignore` lists them.

## Where things are (progressive disclosure)

Paths in the table are from the repo root.

| You're touching… | Go to |
|---|---|
| **A design rule or its reason** | `openHearthStyleGuide.md`. Section 10 is the early plan and parts of it were never built. |
| **What the package exports** | `openhearth_design/lib/openhearth_design.dart` (the barrel file) |
| **A colour value** | `openhearth_design/lib/src/colors.dart` (`OhColors`), then `openhearth_tokens/tokens.css`, `openhearth_tokens/tokens.ts` and the style guide. Pinned in `openhearth_design/test/tokens_test.dart`. |
| **A colour's job (warmth, urgency, warning, attention, success)** | `openhearth_design/lib/src/color_roles.dart` (`OhColorRoles`, one set per theme) |
| **A theme** | `openhearth_design/lib/src/theme.dart` (`OhTheme`: `light()`, `hearthDark()`, `night()`, and the shared `_baseTheme`). Tests: `openhearth_design/test/theme_test.dart`, `openhearth_design/test/contrast_test.dart`. |
| **Type sizes, weights, the ladder, the code face** | `openhearth_design/lib/src/typography.dart`. Tests: `type_ladder_test.dart`, `material_text_theme_test.dart`, `code_face_test.dart` in `openhearth_design/test/`. |
| **Font files** | `openhearth_design/fonts/` (four Lora files, four Nunito files, `OFL.txt`), declared in `openhearth_design/pubspec.yaml`. Tests: `font_bundle_test.dart`, `package_font_render_test.dart`. |
| **Spacing, radii** | `openhearth_design/lib/src/spacing.dart`, `openhearth_design/lib/src/radii.dart` |
| **Shadows** | `openhearth_design/lib/src/elevation.dart` |
| **Durations and curves** | `openhearth_design/lib/src/motion.dart` |
| **The light, dark or follow-phone choice and its app-bar control** | `openhearth_design/lib/src/theme_mode.dart` (`OhThemeModePreference`, `OhThemeToggle`). Test: `oh_theme_mode_test.dart`. |
| **Top-bar commands and the fold rule** | `openhearth_design/lib/src/bar_action.dart` (`OhBarAction`, `OhBarActions`, `OhBarOverflow`, `OhBarFoldable`). Test: `oh_bar_action_test.dart`. |
| **Filled icon buttons** | `openhearth_design/lib/src/icon_buttons.dart` (`OhIconButton`). Test: `oh_icon_button_test.dart`. |
| **The error state and friendly error sentences** | `openhearth_design/lib/src/error_state.dart`, with the sentences and the io split in `openhearth_design/lib/src/errors/`. Test: `oh_error_state_test.dart`. |
| **A failed read of the app's own data (never an empty list)** | `openhearth_design/lib/src/read_error.dart` (`OhReadError`, built on `OhErrorState`), words in `openhearth_design/lib/src/errors/messages.dart`. Test: `oh_read_error_test.dart`, with three goldens. |
| **Confirm before delete, and Undo** | `openhearth_design/lib/src/delete_policy.dart` (`showOhConfirm`, `OhUndoController`, `OhUndoBar`). Test: `oh_delete_policy_test.dart`. The soft-delete contract an app must build is in `README.md`. |
| **Page width on wide windows** | `openhearth_design/lib/src/page.dart` (`OhPage`). Test: `oh_page_test.dart`. |
| **Headlines that must not break mid-word** | `openhearth_design/lib/src/whole_words_text.dart` (`OhWholeWordsText`). Test: `oh_whole_words_text_test.dart`. |
| **Test helpers and the golden image** | `openhearth_design/test/support/` (every style in one map, package font loading), `openhearth_design/test/goldens/` |
| **CSS and TypeScript tokens** | `openhearth_tokens/tokens.css`, `openhearth_tokens/tokens.ts`, `openhearth_tokens/README.md`. No test reads these files. |
| **Version and release notes** | `openhearth_design/pubspec.yaml`, `openhearth_design/CHANGELOG.md` |
| **Lints** | `openhearth_design/analysis_options.yaml` |
| **CI** | `.github/workflows/ci.yml` |
| **How to contribute, licence** | `CONTRIBUTING.md`, `LICENSE` |

## How to work here

```bash
cd openhearth_design
flutter pub get
flutter test        # the command CI runs
```

- **CI** is one workflow. It runs `flutter pub get` and then `flutter test` in
  `openhearth_design`, on a pinned Flutter version, for a push or pull request
  to `master`. It does not run the analyzer and does not build for the web.
  `CONTRIBUTING.md` also asks for `dart format .` and `flutter analyze` before
  review, so run those yourself.
- **The branch is `master`.**
- **A commit** is one concern. Its subject names the area and says what is now
  true, and the message gives the reason. Check the commit identity the repo is
  set to use before the first commit.
- **`openhearth_tokens` has no build and no test.** After you edit `tokens.css`
  or `tokens.ts`, read the two files against `colors.dart` yourself.
- **The font tests read the files in `fonts/` and the pubspec,** so they run from
  the `openhearth_design` folder.
- **A new shared widget** belongs here only when several apps need the same
  behaviour. Otherwise keep it in the app. Add it under
  `openhearth_design/lib/src/`, export it from the barrel file, give it a test
  file, and document it in the README and the changelog.

## When you're unsure

Prefer a failing test to a plausible fix. Prefer matching the code around you to
a new pattern. Prefer the code to the style guide when the two disagree, and say
so in your change. When a rule here does not fit a case, write the case down and
ask before you bend the rule.
