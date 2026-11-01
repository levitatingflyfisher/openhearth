# Vision

> The north star for hearthSync. If you (person or agent) are about to change
> something load-bearing, read this first. It says what must stay true and where
> that is held. For what the parts are, see [README.md](README.md). For where
> things live, see [AGENTS.md](AGENTS.md). For why each decision was made, see
> [docs/adr/](docs/adr/).

## The one idea

**Devices of one household that hold the same signed changes show the same
data, and whatever carries those changes between them cannot read them.**

A household shares twelve words. Each device writes its changes as signed
operations (ops) in a log. Any two devices that hold the same ops compute the
same state, whatever order the ops arrived in. The ops travel sealed, so a relay
stores and forwards bytes it has no key for.

## What this is

A shared library for the OpenHearth fleet of household apps. It has four parts:

- **The kernel** (`kernel/`), one Rust crate. It keeps the signed log, checks
  each op, merges ops into rows, sets and streams, seals what leaves it, and
  hands the app opaque records to store. It has no network code and no storage
  of its own.
- **The Flutter package** (`flutter/hearth_sync/`). It binds the kernel for
  Dart, keeps the device key in the platform's secure storage, stores the
  kernel's records in the app's own database, and carries the relay client and
  the same-Wi-Fi transport.
- **Two relays**, one in Rust (`relay/`) and one in Go (`go-relay/`). Each
  stores sealed ops per household per app and checks signatures. The Go relay
  was written from the protocol page alone, so that the two can check each
  other.
- **Shared vectors and a model** (`vectors/`, `model/`). The vectors pin the
  bytes. The model checks the rules for removing a device and for pruning old
  history.

An app that wants two or more devices of a household to share data declares its
tables, sets and streams, writes through the package, and applies the changes
the package hands back.

```
  app tables  <--  changes  <--  kernel  -->  sealed ops  -->  relay (blind)
      |                            ^                             or
      +-- writes (put, delete) ----+          same Wi-Fi, phone to phone
```

## The invariants (do not break these)

Each one is held by code or a test today. The decision record (ADR) and the
test file are named so you can check.

1. **The kernel is pure.** It does no I/O, reads no clock and draws no
   randomness. Time arrives as `now`, secrets arrive as bytes. Held by
   [ADR 0001](docs/adr/0001-pure-kernel.md) and by `kernel/Cargo.toml`, whose
   dependencies include no randomness crate. This is why the property tests in
   `kernel/tests/props.rs` can replay from a seed.
2. **Same ops, same state, in any order.** Merging is a join, so delivery
   order, duplicates and batching do not change the result. Held by
   [ADR 0003](docs/adr/0003-op-format-and-fold.md) and the properties in
   `kernel/tests/props.rs` (`convergence_in_any_delivery_order`, `idempotence`,
   `commutativity_of_batches`).
3. **One op has one spelling and one id.** Ops are deterministic CBOR, the id
   is the SHA-256 of the signed bytes, and the format is closed. The bytes are
   pinned by vectors built independently in Python. Held by ADR 0003,
   `vectors/` and `kernel/tests/vectors.rs`.
4. **An op is rejected only on what it carries or on its own past.** A check
   that reads local state (the clock, the installed app version) may delay an
   op and may never reject it, or two honest devices would disagree for good.
   Held by [ADR 0004](docs/adr/0004-validity-and-clocks.md) and
   [ADR 0009](docs/adr/0009-app-schemas.md), `kernel/tests/validity.rs`
   (`future_clock_is_quarantined_until_local_time_catches_up`) and
   `kernel/tests/schema.rs`
   (`an_undeclared_name_is_held_until_a_schema_declares_it_then_both_versions_converge`).
5. **A delete is always an explicit op.** It is never inferred from a missing
   row. An edit beats a concurrent delete, and Undo brings a row back whole.
   Held by ADR 0003 and `kernel/tests/scenarios.rs`
   (`edit_beats_a_concurrent_delete`, `reinstall_then_sync_does_not_resurrect`).
6. **App schemas only add names.** A declared name never changes kind or type
   and is never removed. Merging never reads the schema. Held by ADR 0009 and
   `kernel/tests/schema.rs` (`the_fold_is_the_same_whatever_the_schema`).
7. **"Forget this device" agrees everywhere and is never lost.** What the
   forgotten device writes after the cut stops counting on every replica, with
   one stated exception: a Forget cannot reach behind a checkpoint that lacked
   it. The forgotten device wipes its keys. Held by
   [ADR 0002](docs/adr/0002-keys-enroll-forget.md) and
   [ADR 0006](docs/adr/0006-forget-and-horizon-model.md), `kernel/tests/forget.rs`,
   `kernel/tests/model_cx.rs` (one test per counterexample the model found) and
   `model/forget.als`.
8. **Pruning old history changes nothing, and nothing pruned vanishes
   silently.** A returning device's old edits are re-issued under their original
   clock or listed for review. Held by
   [ADR 0005](docs/adr/0005-horizon-snapshots-rebase.md), ADR 0006 and
   [ADR 0007](docs/adr/0007-committed-split-and-fallback.md),
   `kernel/tests/horizon.rs` and the property
   `horizon_state_is_the_unpruned_fold` in `kernel/tests/props.rs`.
9. **Everything that leaves the kernel is sealed.** Ops, snapshots and sync
   messages go out encrypted (XChaCha20-Poly1305) under keys derived from the
   household's words. An envelope opens only in its own household and app,
   under its own id, as its own kind. Held by
   [ADR 0008](docs/adr/0008-sealing.md) and `kernel/tests/seal.rs`.
10. **The device key stays on the platform side, and records are stored before
    anything is sent.** The kernel returns the bytes to sign and takes the
    signature back. A call's records are written, in the kernel's order, before
    its results leave. Held by [ADR 0010](docs/adr/0010-persistence.md),
    [ADR 0011](docs/adr/0011-app-api.md) and
    [ADR 0012](docs/adr/0012-dart-boundary.md), `kernel/tests/api.rs`,
    `kernel/tests/persist.rs` and `flutter/hearth_sync/test/signer_test.dart`.
11. **A relay is blind and trusts only signatures.** It stores envelopes it
    cannot open. Knowing a channel id grants nothing: enrolment and Forget
    need the household key's signature, and every other request a device key's.
    Held by [ADR 0013](docs/adr/0013-relay.md), `relay/tests/conformance.rs`
    and `relay/tests/e2e.rs`.
12. **Both relays give the same answer, byte for byte.** A protocol change
    goes to the protocol page and the vectors first. Held by ADR 0013,
    `vectors/relay_v1.json`, `relay/tests/conformance.rs`,
    `go-relay/internal/relay/conformance_test.go` and the differential harness
    in `go-relay/difftest/`.
13. **Deeply nested input is refused before any decoder recurses.** Bytes from
    someone else cannot crash the kernel or a relay through its decoder. Held by
    ADR 0003 and ADR 0013, `kernel/tests/nesting.rs`, `relay/tests/fuzz.rs` and
    `go-relay/internal/dcbor/dcbor_test.go`.
14. **Sync between two phones on one Wi-Fi needs no server.** The session is
    authenticated by the household's words and a one-time code, and each
    message is checked for order and tampering. Held by
    [ADR 0014](docs/adr/0014-lan-transport.md) and
    `flutter/hearth_sync/test/lan_test.dart`.

## Honest scorecard

A guiding light has to tell the truth about where the light reaches. This code,
its comments and its docs were written by an AI assistant. Treat them as a
record of what currently exists, offered with a grain of salt. Verify a claim
before you rely on it. When sources disagree, the order of authority is
reality, then tests, then code, then comments, then prose docs.

As of November 2026. Nothing was run to write this page. Each line below says
which test files exist, and makes no claim about a run.

**Real, with tests in the repo:**

- **The kernel.** The suite under `kernel/tests/` covers the byte vectors,
  validity, merge scenarios, Forget, the horizon, the model's counterexamples,
  sealing, schemas, persistence, the nesting guard, the app api and the relay
  client's bookkeeping, plus property tests over random three-device histories.
- **The Rust relay.** The suite under `relay/tests/` covers the conformance
  vectors, kernel replicas syncing only through a relay, the HTTP layer and
  the command line, and property-test fuzzing of requests.
- **The Go relay.** Tests sit beside the code under `go-relay/internal/dcbor/`,
  `go-relay/internal/edsig/`, `go-relay/internal/relay/` and
  `go-relay/cmd/hearth-relay-go/`. The differential harness under
  `go-relay/difftest/` drives both relays with the same requests and compares
  every answer.
- **The Flutter package.** The host suite under `flutter/hearth_sync/test/`
  covers sync between devices, persistence, Forget, the review list, the
  signers, the relay client and its wire codec, an end-to-end test that starts
  both relay binaries on localhost, and the same-Wi-Fi transport over a
  loopback socket.
- **The model.** `model/forget.als` is an Alloy model of Forget, checkpoints
  and the horizon. Alloy is a tool that searches small cases for
  counterexamples.
- **The CI file** (`.github/workflows/ci.yml`) names every suite above for
  pushes and pull requests to `master`.

**Built, and unproven in real use:**

- **One app imports the Flutter package.** Lullaby depends on it by path. No
  other app does.
- **No relay is deployed, and no relay image has been built.** The deploy kits
  (`relay/deploy/`, `go-relay/deploy/`, and the home kit in
  `go-relay/deploy/home/`) are files nobody has run for a household.
- **A sync between two real phones in a household is not confirmed.** The
  package README records what has run: a release APK on an Android emulator,
  the web build in headless Chromium, and the same-Wi-Fi transport over
  loopback and between an emulator and a host device. No physical phone, and
  no browser other than Chromium.
- **The model's clean results are bounded.** Each means no counterexample was
  found within a small scope. None is a proof. ADR 0006 lists where the
  implementation departs from the model, and ADR 0007 says which of those
  still stand. The relay path is not in the model.
- **The measurements quoted in the ADRs** come from one machine, and the stage
  reports they cite are not in this repo.

**Designed or named, and not built:**

- **Cutting a forgotten device off from reading.** ADR 0013 names MLS
  (Messaging Layer Security, a standard for group encryption that changes the
  keys when membership changes) as the later answer. Nothing of it exists here.
- **Pruning the index.** ADR 0005, gap 3, is open.
- **Discovery on the local network.** A typed or scanned code is the only way
  to start a same-Wi-Fi session (ADR 0014).
- **An adoption split into small steps.** Adopting a snapshot is one call on
  the UI thread, on the web as well (ADR 0012).
- **A second app.** Every other app in the fleet keeps its current sync.

**Known to be wrong or limited:**

- **A forgotten device can still decrypt.** Until it wipes, it holds the sync
  key and the words. The relay's freeze is the only thing that keeps the
  household's later writes from it (ADR 0013), and a device that has not wiped
  can still sign enrolments and Forgets (ADR 0002). Only a new phrase ends
  that.
- **No forward secrecy.** Someone who records sealed traffic and later learns
  the words can open it (ADR 0014).
- **A Forget cannot reach behind a checkpoint that lacked it.** This is by
  design and it is a limit (ADR 0006, Ruling 1).
- **A self-forgotten device's late edits land without review** (ADR 0006,
  Ruling 2).
- **The index grows forever,** about 100 bytes per op, and a household with
  one device never prunes its own ops (ADR 0005, ADR 0007).
- **Device labels are visible to the relay** (ADR 0013).
- **A self-forgotten device that restarts before posting its record** leaves
  the relay without that device's freeze (ADR 0011, "Limits").
- **Some tests do not run by default.** The performance tests in
  `kernel/tests/perf.rs` and one in `kernel/tests/relay_client.rs` are marked
  ignored. `flutter/hearth_sync/test/bench_test.dart` is skipped unless an
  environment variable is set. The Go memory test is skipped in short mode.
  The differential tests skip when the Rust driver is not built, and the Rust
  relay's end-to-end tests leave the Go relay out when its driver is not named.
  The CI file builds both drivers and fails on a skipped differential test.

Keep that line bright: the merge rules, the formats and the relay protocol have
tests in this repo. A household that syncs every day through a running relay is
still a hope.

## Horizons, as open problems

Framed as problems on purpose. A dated feature list would not survive the work.

- **Does it work in a home?** Two phones, a relay that has run for more than a
  test, a household that depends on it. Everything so far ran on emulators,
  headless browsers and localhost.
- **A removed device that can no longer read.** Today removal stops a device's
  writes from counting and tells it to wipe. It does not take the key away.
  What rotates the key, and how does that fit a log that merges without a
  central order?
- **Twelve words are the household.** Whoever holds them is a full member.
  What should loss and theft of the words cost a family, beyond making a new
  phrase and pairing again?
- **A log that only grows.** The index is never pruned and a lone device never
  prunes. What is the smallest rule that lets history shrink without letting an
  excluded op come back?
- **Schemas that only add, for years.** Names can never change kind or be
  removed. How does an app live with its first choices for a decade?
- **The gap between the model and the code.** The model is partial and its
  scopes are small. Which of the departures can be closed, and can the relay
  path be modelled at all?
- **A second app.** The kernel was written for every syncing app and one uses
  it. What does the next app, with its own existing sync, have to give up or
  gain to move?

## The name

**hearthSync** is the sync for one hearth: the household that the OpenHearth
fleet is built around. The name carries the scope. It syncs a home's own
devices with each other, with no account and no service that knows what the
home wrote.
