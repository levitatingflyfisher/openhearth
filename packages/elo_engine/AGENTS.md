# AGENTS.md

This codebase is yours: what it's for and how it's built are your call, and you'll keep building on it.

Guidance for AI coding agents (and humans) working in this repo. This is the
top-level map. Read it before any work that is more than a typo.

**Read these, in order, before you change anything load-bearing:**
1. [VISION.md](VISION.md): what must stay true, and the honest scorecard.
2. [doc/reference/api.md](doc/reference/api.md): the engine, its config and its result types.
3. The page under [doc/explanation/algorithms/](doc/explanation/algorithms/) for any algorithm you touch. Each page says what this code runs.

## The grain-of-salt law

Every line of source and every comment here was written by an AI assistant.
Treat it as **an accurate record of what currently exists, offered with gratitude
and a grain of salt**. It is no specification and it is not guaranteed correct. A
comment that claims an invariant is a hypothesis to verify. When sources
disagree, the order of authority is: reality, then tests, then code, then
comments, then prose documents.

Two live examples. A comment in `lib/src/ranking_comparison.dart` says the
SerialRank order comes from a Fiedler vector, and the code sorts by mean win
rate. A comment in `lib/src/models.dart` says a skip is never kept in history,
and `record` keeps it. Confirm before you rely.

## What this is

A pure-Dart library that ranks items from pairwise picks: the app asks for the next pair, records the pick, and reads a ranking back.
It keeps a live Elo rating, can run up to fifteen ranking methods over the same history, and can merge several people's private rankings.
It has no screen, no storage and no network code. Lilt and Mantle import it by path.

## Non-negotiables (a change must not break these)

- **Pure Dart, no runtime dependency.** `pubspec.yaml` has no `dependencies`
  block. Do not add one. No `flutter` import, no `dart:io`, no `dart:html`, no
  network call. The library must keep compiling to JavaScript, because the apps
  that use it ship web builds.
- **No storage and no screen.** The library returns JSON maps. The app decides
  where they go.
- **One public import.** Apps import `package:elo_engine/elo_engine.dart`. A new
  public type must be exported from `lib/elo_engine.dart`. The algorithm
  functions in `batch_algorithms.dart`, `parametric_algorithms.dart` and
  `elo_math.dart` stay internal.
- **The match history is the source of truth.** Ratings are rebuilt by replay
  (the constructor, `undo`, the default `fromJson`). Do not add state that
  replay cannot rebuild.
- **A skip moves no rating and stays in the history.** Pair proposal and undo
  both depend on it.
- **A disabled algorithm has no influence** on the consensus, the agreement
  score or the rank spreads.
- **Merge combines rankings, never raw picks.** Each person's history stays
  their own.
- **Save and restore round-trip.** What `toJson` writes, `fromJson` must read
  back, for the engine, the config, items, matches and sessions. An app may
  have stored that JSON, so a renamed key can break saved data.
- **Docs say what the code runs.** If you change an algorithm, change its page
  under `doc/explanation/algorithms/`, the README table and the VISION
  scorecard in the same piece of work. Do not describe a published method the
  code does not implement.
- **A change ships with its test.** `CONTRIBUTING.md` asks for tests with every
  new feature. A bug fix ships a test that failed before the fix.
- **Small commits, one concern each.** The message states why. **No AI
  attribution lines** (`Co-Authored-By`, "Generated with"). This is project
  policy.
- **Never commit** `CLAUDE.md`, `GEMINI.md` or `docs/superpowers/`. They are
  local working files and are listed in `.gitignore`.

## How to work here

The CI file, `.github/workflows/ci.yml`, runs these on every push and pull
request to `master`:

```bash
dart pub get
dart test                                   # the whole suite under test/
dart test -p node test/session_id_test.dart # the web-sensitive test, compiled to JavaScript
```

- **The branch is `master`.** `CONTRIBUTING.md` says `main`. That file is out of
  date on this point.
- **Lint.** `analysis_options.yaml` turns on strict casts, strict inference,
  strict raw types and `public_member_api_docs` for `lib/`. Every public member
  needs a doc comment. `CONTRIBUTING.md` asks for `dart analyze` and
  `dart format .` before review. The CI file does not run either, so run them
  yourself.
- **Speed.** `dart run benchmark/main.dart` exits non-zero when a timing guard
  fails. The CI file does not run it. Run it after a change under `lib/src/`.
- **On a version tag** the CI file also runs `dart pub publish --dry-run`.
- **A commit** is one concern, with a plain subject line that says why the
  change was made, and no attribution footer.
- **Adding an algorithm** touches five places: the `AlgorithmId` enum in
  `lib/src/models.dart`, the function in `batch_algorithms.dart` or
  `parametric_algorithms.dart`, the field on `RankingComparison`, the wiring in
  `compareAlgorithms` and `_anyBatchEnabled` in `lib/src/engine.dart`, and a
  test. Then the docs: a page, the README table, `doc/reference/api.md`.

## Where things are (progressive disclosure)

| You are touching... | Go to |
|---|---|
| **What apps can import** | `lib/elo_engine.dart` (the barrel, eight exports) |
| **Record, undo, next pair, the stopping signal, the ensemble, save and restore** | `lib/src/engine.dart` (`EloEngine`) |
| **Items, matches, outcomes, config, the algorithm ids** | `lib/src/models.dart`. Several doc comments here are known to be stale: the one-line notes on `hodge`, `serialRank` and `matrixFactorization` in `AlgorithmId`, the note on `EloItem.lastSeen`, and the note on `EloMatch.outcome` about skips. Trust the code. |
| **Elo arithmetic, K-factor stages, Kendall's tau** | `lib/src/elo_math.dart` (internal) |
| **Glicko-2** | `lib/src/glicko2.dart` |
| **TrueSkill** | `lib/src/trueskill.dart` |
| **Win and tie counts, win rates** | `lib/src/pairwise_matrix.dart` (the input to every batch method; read the warning on `ties`) |
| **Borda, Copeland, PageRank, Markov, Schulze, Ranked Pairs** | `lib/src/batch_algorithms.dart` (internal) |
| **Bradley-Terry, Thurstone, SpringRank, HodgeRank, SerialRank, matrix factorization** | `lib/src/parametric_algorithms.dart` (internal). For the last three, the doc comments on `hodgeRanking`, `serialRanking` and `matrixFactorizationRanking` are the closest to what runs. |
| **The result types of the ensemble** | `lib/src/ranking_comparison.dart`. Several doc comments here are known to be stale: the Fiedler vector on `SerialRankResult`, both magnitudes on `HodgeResult`, the rank range on `MatrixFactorizationResult`, and "conservative skill" on `glicko2Ranking`. Trust `parametric_algorithms.dart` and `engine.dart`. |
| **Merging several people's rankings** | `lib/src/merge.dart` (`EloMerge`, `MergeStrategy`, `MergedResult`) |
| **A session snapshot, the sync placeholders, the session id** | `lib/src/session.dart` (only `SyncMode.standalone` does anything) |
| **Tests for the engine** | `test/engine_test.dart`, `test/enabled_algorithms_test.dart` |
| **Tests for one algorithm family** | `test/elo_math_test.dart`, `test/glicko2_test.dart`, `test/trueskill_test.dart`, `test/pairwise_matrix_test.dart`, `test/batch_algorithms_test.dart`, `test/parametric_algorithms_test.dart` |
| **Tests for merge and sessions** | `test/merge_test.dart`, `test/session_id_test.dart` (also run on `node`) |
| **Timings and the regression guards** | `benchmark/main.dart` |
| **The runnable demo** | `example/main.dart` |
| **The docs hub** | `doc/README.md` |
| **A first walkthrough** | `doc/tutorial/getting-started.md` |
| **Recipes** | `doc/how-to/` (save and restore, merge, subsets, convergence, undo) |
| **Type and method reference** | `doc/reference/api.md` |
| **Which algorithm to pick** | `doc/explanation/choosing-an-algorithm.md` |
| **What one algorithm does, here and as published** | `doc/explanation/algorithms/` (one page each, fifteen pages) |
| **What the CI runs** | `.github/workflows/ci.yml` |
| **Package name, version, SDK range, dev dependencies** | `pubspec.yaml` |
| **Lint rules** | `analysis_options.yaml` |
| **How to contribute** | `CONTRIBUTING.md` (its branch name is out of date, see above) |
| **Old requirements** | `eloEnginePRD.md`. History only. Read the dated note at its top first. The README is the current description. |
| **The front door, the algorithm table, the timings** | `README.md` |
| **Licence** | `LICENSE` (MIT) |

Docs follow the [Diátaxis](https://diataxis.fr/) split: tutorial, how-to,
reference, explanation. See [doc/README.md](doc/README.md).

## When you are unsure

Write the failing test before the fix. Match the code around you before you
bring in a new pattern. Prefer saying "this code runs a simpler method" to borrowing the
credit of a published name. When a comment and the code disagree, the code is
right and the comment is the thing to report.
