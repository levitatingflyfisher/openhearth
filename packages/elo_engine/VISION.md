# Vision

> The north star for `elo_engine`. If you (person or agent) are about to change
> something load-bearing, read this first. It says what must stay true and why.
> For how to use the library, see [doc/README.md](doc/README.md). For what each
> algorithm does in this code, see the pages under
> [doc/explanation/algorithms/](doc/explanation/algorithms/).

## The one idea

**A person only ever picks between two things. The library turns those picks
into a ranking, and says how far that ranking can be trusted.**

Putting fifty items in order is hard. Choosing between two is easy. So the app
asks the easy question many times and the library computes the hard answer.

Then it checks its own answer. It runs several ranking methods over the same
picks. Where the methods agree, the order is solid. Where they disagree, the
library reports which items are in doubt.

## What this is

A **pure-Dart library for ranking by pairwise comparison**. It has no screen, no
storage and no network code. An app hands it a list of item ids, asks which pair
to show next, records each pick, and reads the ranking back.

It is made for apps where a household chooses among many things. Two apps import
it today, each by a path dependency: Lilt (baby names for couples) and Mantle (a
household's shared style).

```
  the app asks               the library keeps             the app reads
 ───────────────────        ───────────────────        ───────────────────────
  nextMatch()                the match history           rankings, isConverged
  record(a, b, outcome) ──▶  (the one source of    ──▶   compareAlgorithms()
  undo()                     truth)                      EloMerge.combine()
```

What it does, in plain words:

- **Proposes the next pair.** It prefers items it knows little about and pairs
  that look close, and it avoids a pair it showed in the last few matches.
- **Keeps a live rating.** Each pick updates an Elo rating at once. Glicko-2 and
  TrueSkill states are updated beside it.
- **Says when to stop.** `isConverged` turns true when the order has stopped
  moving.
- **Runs an ensemble on request.** `compareAlgorithms()` runs up to fifteen
  methods over the same history and returns each ranking, a consensus ranking,
  an agreement score, and how far each item's rank spreads across the methods.
- **Merges private rankings.** Several people rank the same items apart.
  `EloMerge.combine` joins their rankings and reports agreement per item.
- **Saves, restores and undoes.** State goes to and from a JSON map. The app
  decides where that map is stored.

## The invariants (do not break these)

Each of these is held today by the code or by a test. The file or test is named.

1. **Pure Dart, no runtime dependency, no input or output.** `pubspec.yaml` has
   no `dependencies` block, only `lints` and `test` for development. Every file
   under `lib/src/` imports only `dart:math`, `dart:collection` and its
   neighbours. The library never opens a file or a socket.
2. **One import.** Apps use `package:elo_engine/elo_engine.dart`. That barrel
   (`lib/elo_engine.dart`) exports eight files. `elo_math.dart`,
   `batch_algorithms.dart` and `parametric_algorithms.dart` are internal.
3. **The match history is the source of truth.** Ratings are rebuilt by replay.
   The constructor replays a given history, `undo()` resets and replays, and
   `fromJson` replays by default and ignores the stored ratings
   (`lib/src/engine.dart`). Tests: the groups `EloEngine.undo` and
   `EloEngine JSON serialization` in `test/engine_test.dart`. The one exception
   is the explicit `skipReplay: true` option, which accepts stored ratings.
4. **A skip changes nothing but is remembered.** A skipped pair moves no rating
   and no match count, and it never enters the pairwise matrix. It does stay in
   the history, so the pair is not proposed again at once and undo stays
   correct. Tests: `skip does not change ratings or matchCount` and
   `undo after skip reverts correctly (skip is in history)` in
   `test/engine_test.dart`, `skips are excluded from win and tie counts` in
   `test/pairwise_matrix_test.dart`.
5. **A disabled algorithm has no influence.** It appears as `null` and is left
   out of the consensus, the agreement score and the rank spreads. An empty set
   of algorithms is refused when the engine is built. Tests:
   `test/enabled_algorithms_test.dart`.
6. **Bad input fails loudly.** Duplicate item ids, an unknown id, a tie when ties
   are turned off, and a merge over different item sets each throw an
   `ArgumentError`. Tests: the group `EloEngine.record` in
   `test/engine_test.dart`, `throws on mismatched item ID sets` in
   `test/merge_test.dart`.
7. **Merging reads each person's ranking and nothing else.** `EloMerge.combine`
   sorts each session by rating and combines rank positions. It never pools the
   picks of two people into one history (`lib/src/merge.dart`). Test:
   `end-to-end: two engines → snapshots → merge` in `test/merge_test.dart`.
8. **It runs on the web as well.** The session id generator avoids a 32-bit
   shift that fails when compiled to JavaScript (`lib/src/session.dart`). Test:
   `test/session_id_test.dart`, which the CI file also runs on the `node`
   platform.

## Honest scorecard

This section separates what is proven from what is hoped. Each line below was
checked by reading the code and the test files. Nothing was run for
this page, so it gives no pass counts. As of version 0.1.0, November 2026:

**Real, and covered by the suite under `test/`:**

- **The core loop**: `record`, `rankings`, `nextMatch`, `undo`, `isConverged`
  (`test/engine_test.dart`).
- **The Elo arithmetic**, the K-factor stages and Kendall's tau
  (`test/elo_math_test.dart`).
- **Glicko-2 and TrueSkill** per-match updates (`test/glicko2_test.dart`,
  `test/trueskill_test.dart`). Each file has one worked value, derived by hand
  from the published formulas in the test's own comments.
- **The pairwise matrix** built from history (`test/pairwise_matrix_test.dart`).
- **Borda, Copeland, PageRank, Markov, Schulze and Ranked Pairs**
  (`test/batch_algorithms_test.dart`).
- **Bradley-Terry, Thurstone, SpringRank** and the three methods described
  under "known to be wrong" below (`test/parametric_algorithms_test.dart`).
- **Choosing a subset of algorithms** (`test/enabled_algorithms_test.dart`).
- **Merge** with its three strategies (harmonic mean, arithmetic mean, minimum),
  `snapshot`, and session JSON (`test/merge_test.dart`).
- **JSON save and restore** of the engine, with and without replay
  (`test/engine_test.dart`).

**Built, and unproven:**

- **Whether the rankings are right.** The tests use small made-up cases of at
  most five items, mostly a clean "a beats b beats c". No test compares any of the
  fifteen methods with a published data set or a reference implementation.
- **The timings in the README.** They come from `benchmark/main.dart`. The CI
  file does not run the benchmark, so its regression guards fire only when
  someone runs it by hand.
- **The pair chooser.** It scans every pair with a simple score. Tests check
  a handful of its behaviours. Nothing measures how many questions it saves.
- **The stopping signal.** Two tests cover it. The default thresholds are a
  rule of thumb.
- **Restore with `skipReplay`.** Tested on three items for ratings and order.
  The window of past orders that `isConverged` uses is not saved, so a restored
  engine starts that window empty.
- **The save format.** `toJson` writes `version: 1`. `fromJson` does not read
  it, so there is no check on a file from another version.
- **Skipping work for disabled Glicko-2 and TrueSkill.** The code skips the
  per-match updates. The tests can only see that the result is `null`.
- **Lint and format.** `CONTRIBUTING.md` asks for `dart analyze` and
  `dart format`. The CI file runs only the tests.
- **Publishing.** The version is 0.1.0 and `pubspec.yaml` says the package has
  not had its first pub.dev publish. Apps depend on it by path.

**Designed, and not built:**

- **Any sync between devices.** `SyncMode.asyncMerge` and
  `SyncMode.liveSession` are placeholders, and `sessionCode`,
  `hostParticipantId` and `expiresAt` are carried and never used
  (`lib/src/session.dart`). Merge works on sessions that are already in one
  place.
- **The list of preference cycles, the named preference dimensions, and a
  minimum-data threshold** that the old requirements file promised. The code
  reports magnitudes only, and every enabled algorithm returns a result however
  little data it has. See the note at the top of
  [eloEnginePRD.md](eloEnginePRD.md).
- **Item coordinates from matrix factorization.** The code returns a rank count,
  a share of variance and one ranking.

**Known to be wrong, or named for more than it does:**

- **SerialRank runs a simpler method than the published one.** The published
  SerialRank is a spectral method. This code orders items by their mean win
  rate against all other items, with a pair never compared counted as 0.5. Its
  `rankability` is the share of compared pairs whose record agrees with that
  order. No eigenvector is computed.
- **HodgeRank runs a simpler computation than the published one.** The code
  fits a least-squares ranking to centred win rates, where the published method
  commonly uses log-odds. `cyclicMagnitude` is the size of everything that fit
  leaves unexplained. It is not split into a cyclic part and a harmonic part.
  `harmonicMagnitude` is the share of item pairs never compared. It measures
  coverage and is no harmonic component.
- **Matrix factorization is a small eigenvector search.** It finds at most
  three directions by power iteration and reports the smallest count that
  explains 80% of the variance. A code comment calls it non-negative matrix
  factorization. It is not that.
- **The batch methods count ties three ways.** Bradley-Terry, Thurstone and SpringRank
  count a tie as half a win for each side. The win-rate matrix that feeds
  HodgeRank, SerialRank and matrix factorization counts a tie as a win for
  neither, so the two rates of a pair with ties add up to less than one. Borda,
  Copeland, PageRank, Markov, Schulze and Ranked Pairs ignore ties.
- **Several code comments are stale**, in `lib/src/models.dart` and
  `lib/src/ranking_comparison.dart`. Examples: a comment says a skip is never
  kept in history, and the code keeps it. A comment says the SerialRank order
  comes from a Fiedler vector. Trust the code.
- **`CONTRIBUTING.md` names the branch `main`.** The repository and its CI file
  use `master`.

Keep that line bright. The loop, the merge and the save format work on one
device and have tests. The three deep methods are simpler than their names.
Nothing here has been checked against outside results.

## Horizons (open problems)

These are framed as problems on purpose. A dated feature list goes stale.

- **Is the ranking right?** Each method needs a check against results that were
  not made up for the test.
- **Names that match the code.** SerialRank and HodgeRank either grow into their
  published forms or take names that fit what runs.
- **One meaning for a tie** across all the methods, or a clear reason for the
  difference.
- **Two people, two devices, no server.** The session type already carries the
  fields. The hard part is a merge that stays private and needs no account.
- **Fewer questions.** How few picks give an order a household can trust, and
  how would anyone measure that?
- **Words for the numbers.** The library can say that two people disagree, or
  that the picks run in a circle, only as a number. Turning that into a sentence
  a household can use is unsolved.
- **A save format that can change safely**, since the version field is written
  and never read.

## The name

The package is `elo_engine`, named for Elo, the rating method most people have
heard of. Elo is the live rating that every pick updates. The name covers only
part of the library, which runs fifteen methods and compares them.

## A grain of salt

This code, its comments and its documents, this page included, were written by
an AI assistant. Treat them as a record of what exists today, offered with a
grain of salt. They are no specification. When sources disagree, the order of
authority is: reality, then tests, then code, then comments, then prose
documents. Verify a claim before you rely on it.
