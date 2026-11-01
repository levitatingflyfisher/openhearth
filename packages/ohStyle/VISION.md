# Vision

> The north star for ohStyle. If you (person or agent) are about to change a token,
> a theme or a shared widget, read this first. It says what must stay true and why.
> For how to use the package, see [README.md](README.md). For the reasoning behind
> each design rule, see [openHearthStyleGuide.md](openHearthStyleGuide.md).

## The one idea

**Every OpenHearth app speaks one shared design grammar and keeps its own
personality.**

A family that opens a second OpenHearth app should feel at home at once. The
colours, the type, the spacing and the manners (how an error reads, how a delete
is undone, where the theme control sits) come from one place. Each app then adds
its own accent colour and its own character on top.

The second half of the idea is that the grammar is checked by tests wherever a
test can check it. Contrast is measured for every pair the themes wire. Every
text size sits on one ladder. Every font a style asks for is a file in the
package.

## What this is

The shared design package of the OpenHearth fleet. It has two parts and a guide.

```
  openHearthStyleGuide.md        the written rules and the reasons for them
          |
          +--> openhearth_design/    Flutter package: tokens, three themes,
          |                          bundled fonts, shared widgets
          |
          +--> openhearth_tokens/    tokens.css and tokens.ts, kept by hand,
                                     for projects that do not use Flutter
```

- **`openhearth_design`** is a Flutter package. It gives an app the colour ramps
  (`OhColors`), the colour roles (`OhColorRoles`), spacing, radii, elevation,
  motion, the typography roles (`OhTypography`), three themes (`OhTheme.light()`,
  `OhTheme.hearthDark()`, `OhTheme.night()`), the Lora and Nunito font files, and
  a small set of shared widgets: the error state, the confirm dialog and Undo
  bar, the theme toggle, the page width cap, whole-word headlines, top-bar
  commands and two icon buttons. A Flutter app in the fleet depends on it by
  path, as the README shows. It is not published to pub.dev.
- **`openhearth_tokens`** is two static files, `tokens.css` and `tokens.ts`, with
  the same values for a web or desktop frontend. There is no build step and no
  npm package.

The package holds look and shared behaviour only. It stores nothing, makes no
network call, and has no knowledge of any app's data.

## The invariants (do not break these)

Each one is held today by the code or by a test under
`openhearth_design/test/`. The file that holds it is named.

1. **Every colour pair the themes wire clears WCAG AA.** Text needs 4.5:1 and
   marks (icons, a field's only border) need 3:1, on the scaffold, the card and
   the raised container, in all three themes. Held by `test/contrast_test.dart`,
   which reads the built `ThemeData` and the `OhColorRoles` each theme carries.
2. **Three themes, one builder.** `light()`, `hearthDark()` and `night()` all go
   through the same private builder in `lib/src/theme.dart`, so a slot wired in
   one is wired in all. Each takes an `appAccent`. `test/theme_test.dart` pins
   each theme's default colours and the accent override.
3. **Warmth and urgency are separate roles, and chrome is neutral.** The brand
   colour never stands for an error or a destructive act, and plain icons take
   the neutral colour. Held by the "colour language wiring" group in
   `test/theme_test.dart`. A destructive confirm also carries an icon, so the
   danger does not rest on colour alone (`test/oh_delete_policy_test.dart`).
4. **Fonts come from the package and nothing is fetched.** Every Lora or Nunito
   style names the package font, and every (family, weight, style) a style asks
   for is a real file in `openhearth_design/fonts/`, checked against the file's
   own OS/2 table. Held by `test/font_bundle_test.dart` and
   `test/package_font_render_test.dart`.
5. **One type ladder.** Every size any role or Material slot uses is on
   `OhTypography.ladder`, and no two sizes in use are within 2 px. Held by
   `test/type_ladder_test.dart` and `test/material_text_theme_test.dart`.
6. **A raw exception is never the main text.** `OhErrorState` shows a plain
   sentence and keeps the technical error behind Details.
   `ohFriendlyErrorMessage` never returns the exception's own text. Held by
   `test/oh_error_state_test.dart`.
7. **Undo does not expire on a timer.** `OhUndoController` and `OhUndoBar` in
   `lib/src/delete_policy.dart` hold no timer. The offer ends only when the
   person acts. `showOhConfirm` asserts that its confirm label names the act.
   Held by `test/oh_delete_policy_test.dart`.
8. **The theme choice defaults to following the phone.** A missing or unknown
   stored value reads back as the default. Held by `lib/src/theme_mode.dart` and
   `test/oh_theme_mode_test.dart`.
9. **A top-bar command has one name and a 48 dp target, worded or folded.** Held
   by the "the one name" and "tap target" groups in
   `test/oh_bar_action_test.dart`.
10. **The package depends on the Flutter SDK alone.** No font fetcher, no icon
    package, no network or storage library. Held by
    `openhearth_design/pubspec.yaml`. No test checks it.
11. **The package compiles where `dart:io` does not exist.** The io exception
    types sit behind a conditional import in `lib/src/error_state.dart` and
    `lib/src/errors/`. Held by the code. No test or CI step builds for the web.

## Honest scorecard: built and not built

A guiding light has to tell the truth about where the light reaches. This code,
its comments and these docs were written by an AI assistant. Treat them as a
record of what exists, offered with a grain of salt, and verify a claim before
you rely on it. When they disagree, the order of authority is: reality, then
tests, then code, then comments, then prose docs.

Every line below was checked by reading the files in November 2026. Nothing was
run for this page, so "tested" here means the test file exists in the suite under
`openhearth_design/test/` and was read. No test in the suite is marked as
skipped. As of package version 0.9.3:

**Real and tested:**
- **The Dart tokens.** Colours, spacing, radii, elevation and motion.
  `test/tokens_test.dart` pins every hearth and linen step, the spacing scale and
  the radii. It pins only some of the sage, slate, amber, red and surface
  colours.
- **The three themes** and their colour roles (`test/theme_test.dart`,
  `test/contrast_test.dart`).
- **Typography.** The role methods, the Material text theme, the ladder, the
  code face (`test/type_ladder_test.dart`, `test/material_text_theme_test.dart`,
  `test/code_face_test.dart`).
- **Bundled fonts.** Eight font files and `OFL.txt` in `openhearth_design/fonts/`,
  declared in the pubspec as package fonts (`test/font_bundle_test.dart`,
  `test/package_font_render_test.dart`, with one golden image).
- **The shared widgets,** each with its own test file: `OhErrorState`,
  `OhReadError`, `showOhConfirm` and `OhUndoBar`, `OhThemeToggle`, `OhPage`,
  `OhWholeWordsText`, `OhBarAction` with `OhBarActions` and `OhBarOverflow`, and `OhIconButton`.
- **CI.** One workflow runs the suite with `flutter test` in `openhearth_design`
  on a push or pull request to `master`.

**Built and unproven:**
- **`tokens.css` and `tokens.ts`.** They exist and are kept by hand. No test in
  this repo reads either file. On a read by eye their colour values matched the
  Dart colours. The style guide's tables were not compared value by value.
- **The web tokens cover less than the Dart package.** The CSS file has a light
  set and one dark set, switched by `prefers-color-scheme`. The night colours
  are there as plain values, but no semantic set uses them. The TypeScript file
  has no semantic set at all.
- **Web builds.** The conditional import is in place, but CI runs only the test
  suite. It does not build for the web and does not run the analyzer.
- **Look.** The tests measure contrast, sizes, layout and screen-reader names.
  Goldens exist for font rendering and for `OhReadError` in each of the three
  themes. No other widget has a golden.
- **The soft-delete contract** behind the Undo bar is prose in the README. Each
  app has to build it, and nothing here can check that it did.

**Designed and not built:**
- Section 10 of the style guide is the early plan, and it carries a note saying
  so. There is no `components/` folder of buttons, cards and inputs, no icon
  package, no React component set and no Tailwind preset.
- Nothing is published to pub.dev or npm. The pubspec says `publish_to: none`.
- Illustration and photography style. The style guide lists both as undecided.

**Known to be wrong:**
- **The token values live in four hand-kept places:** the style guide,
  `openhearth_design/lib/src/colors.dart`, `openhearth_tokens/tokens.css` and
  `openhearth_tokens/tokens.ts`. Only the Dart file is under test. A change that
  misses one of the other three fails nothing.
- **Two other repos keep their own older copies** of the CSS file, and no project
  imports the files here in place. Those copies have drifted: they hold older
  hearth, red and amber values and lack the newer steps. The README lists the
  differences. A change here does not reach them.
- **Small differences between the Dart and web tokens.** The pill radius is 999
  in Dart and 9999 in CSS and TypeScript. The web files name a JetBrains Mono
  font, and the Dart package says no such file is bundled anywhere.
- **`OhMotion.emphasized` has the same curve values as `standardCurve`.**
- **The style guide disagrees with the code in places.** It says an app with no
  stored choice should start in light and should not follow the system. The code
  defaults to following the phone. It names an icon library that the package
  does not depend on. The code governs.
- **Stale pointers.** Comments in `theme.dart`, `colors.dart` and `tokens.css`
  point to a `CLAUDE.md` that is not in the repo. The header comments in the two
  token files give paths that do not match this repo's layout. The 0.7.0 entry in
  the changelog gives a value for `hearth500` that the code later darkened.

The line to keep bright: the Dart package is the part under test. The style
guide, the CSS file and the TypeScript file are kept in step by hand and by
nothing else.

## Horizons (open problems)

Framed as problems on purpose. A dated feature list goes stale.

- **Near: copies drift.** Four hand-kept places and two outside copies cannot
  stay equal by care alone. The open problem is how to make one of them the
  source and have a test fail when another disagrees.
- **Near: the web side is thinner.** A web or desktop frontend gets colours and
  spacing but no night theme and none of the shared behaviour. What should a
  project without Flutter be able to rely on?
- **Mid: one change, many apps.** A token change alters how every consuming app
  renders, and each app re-approves its own golden images. Nothing shows the
  effect of one change across the fleet in one place.
- **Mid: sameness against identity.** Shared widgets remove drift, and they can
  also flatten the apps into one template. Where the shared grammar should stop
  and an app's own character begin is still decided case by case.
- **Far: checking what a test cannot measure.** Contrast and size are numbers.
  Warmth and calm are not. The style guide asks for both, and today only a
  person looking at a screen can say whether a change kept them.
- **Far: pictures.** The style guide leaves illustration and photography
  undecided. The grammar covers colour, type and behaviour, and has no answer
  yet for what an OpenHearth picture looks like.

## The name

**ohStyle.** "oh" is the fleet's short prefix for OpenHearth. It is on every
class in the package (`OhColors`, `OhTheme`, `OhPage`) and every CSS variable
(`--oh-`). The hearth is the warm centre of a home, and the main colour ramp and
the warm dark theme are named for it.
