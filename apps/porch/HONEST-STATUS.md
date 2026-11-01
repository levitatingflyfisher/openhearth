# HONEST-STATUS — what is real, what is not

> Rule (BUILD-SPEC §6): this file is updated in the same change as any claim
> it covers. Overclaiming is the cardinal sin.
>
> Updated by: **W1-relay package** (first package landed; `relay/`, compose, Caddyfile),
> then **W2-domain package** (`app/` scaffold + `app/lib/domain/`),
> then **W3-data package** (`app/lib/data/` — relay client, persistence,
> repositories, sync),
> then **W4-ui package** (`app/lib/presentation/` + `bootstrap.dart` +
> the remaining data services),
> then **W5-finisher** (verification pass, rotation fan-out jitter, the
> compiled-relay integration harness, ops/, README — and this final
> scorecard).

## Fleet adoption (2026-09-28)

porch now builds on the fleet design package and is held to the fleet
checks. What is real and tested, and what is not:

- **Theme:** `openhearth_design`'s `OhTheme` with porch's amber as the
  accent (contrast pinned in `theme_test`); light / dark / follow the
  phone, stored under `porch.theme.v1`, two taps from Home (More menu)
  and on Settings (`theme_and_width_test`). Every screen width-capped by
  `OhPage`.
- **Fleet conformance** (`app/test/fleet_conformance_test.dart`): C1, C4
  (exactly `INTERNET`), C6, C7, C8, C10, C11, C12 and C5-primaryScreens
  pass. C2, C3 and C9 are off, each with its reason in that file;
  `screen_doors_test` stands in for C9.
- **CI** (`.github/workflows/ci.yml`) exists since 2026-09-28 and **has
  never run**: nothing is pushed.
- Not verified anywhere but the host: the theme read before `runApp`,
  the boot screen, the launcher label, the new manifest permission.

## The scorecard (W5-finisher — final for this build)

Suite totals: the app's full suite was counted again on 2026-11-14 (below).
The relay's tests are run but not counted. What was checked since:

| Suite | Command | Result |
|---|---|---|
| Relay | `go test -race ./...` (no services) | all 4 packages ok, 156 tests and subtests passed, 2026-11-15; the 6 Redis-backed tests skip without `REDIS_URL` |
| Relay | `REDIS_URL=… go test -race -p 1 -count=1 ./...` vs live Redis 7 | all 4 packages ok, 191 tests and subtests passed, 0 skipped, 2026-11-15, after the bulletin writer change: Redis 7.4.12 (linux/amd64 digest `sha256:a6dd4287…3094`), 32 MB `maxmemory`, `noeviction`. **`-p 1` is required:** the store and api packages flush the same Redis, so packages run side by side wipe each other's data mid-test (without it, the full-memory test failed with "mail lost"; alone it passed) |
| Relay | `go vet ./...` | clean, 2026-11-15 |
| App | `flutter test` (full suite) | 516 passed, 0 failed, run twice, 2026-11-15 (run in a capped memory scope) |
| App | `flutter analyze` | no issues, 2026-11-15 |

The per-package test counts in the sections below are historical
snapshots from when each package landed, not current totals. Builds: an
arm64 release APK and a web build were each made once, on 2026-07-10 (see
"Android build" below); neither has been rebuilt since, so neither carries
anything after that date, and that APK could not reach a relay (no
`INTERNET` permission, fixed since). Neither has ever run on a device.

### New and real in the W5-finisher package

- **Rotation fan-out jitter (§1.6/§3.6/W5 acceptance)** — each sealed
  rotation mailbox POST now carries an independent random delay in
  [0, 30] s (`OutboxEntry.notBefore`; production randomness =
  `sodium.randombytes.uniform`, schedule injectable through `PorchEnv` and
  a `rotationJitterProvider` — the same seam tests and bootstrap share).
  The outbox HOLDS not-yet-due entries without counting an attempt and
  without blocking later due entries, so the optimistic tap path never
  waits behind a jittered bundle (safe: bundles are epoch-guarded and
  self-contained). Unit-tested: scripted schedules land at exactly now+5 /
  now+30; nothing reaches a mailbox early; the production default draws
  within bounds; old state files (no `notBefore` field) read as
  due-immediately. Scenario/UI suites inject zero jitter for deterministic
  transcripts — documented in the harnesses.
- **The compiled-relay integration harness**
  (`app/test/data/relayd_integration_test.dart`) — closes W3's biggest
  named gap ("twinned fakes, not proven interop"). The test **compiles the
  actual Go `relayd`**, boots it on an ephemeral localhost port (memstore),
  and drives two REAL clients — production `HttpRelayApi`, repositories,
  and `SyncService`, real wall clock — through the full transcript:
  onboard ×2 → group → invite mint → redeem → fulfill → grant (verified
  delete-after-retrieval on the real wire) → mutual presence (each device
  reads the other's tag through real envelopes over real HTTP) → silent
  leave → admin rotation (epoch 2, new channel address) → departed member
  drains an empty mailbox. Afterward it asserts the relay process emitted
  **zero bytes** on stdout+stderr across the whole transcript, and kills it
  via SIGTERM (the graceful-shutdown path). If `go` is missing the test
  skips VISIBLY with a reason. Bonus finding: the relay's drain replay
  cache fired for real when a same-second re-drain produced a
  byte-identical Ed25519 signature — the protection works on the wire, and
  the test documents why its probe nudges `ts`.
- **`relay/ops/porchd.service`** — hardened systemd unit (DynamicUser, strict
  sandboxing, streams to `null` to match the binary's structural silence);
  **`relay/ops/DEPLOY.md`** — compose + bare-metal walkthroughs, flag table, and
  the "if logs ever appear, that's a sev-1 privacy bug" post-deploy check.
  Written against the compose stack W1 verified; the Hetzner walkthrough
  itself has NOT been executed against a live VM.
- **`README.md`** — what Porch is, the one idea, how to run app/relay/
  tests, and the short-form threat model with the residuals named.

### Still absent after W5 (nothing below is claimed)

- **Widget bridge**: `home_widget` writer, Android AppWidget +
  long-press-toggle background callback, iOS WidgetKit/AppIntent. The
  `WidgetCacheMirror` port + contract JSON builder are real and tested
  (W3); production still binds `NoopWidgetCacheMirror`. The app is
  complete without the widget, as the spec designed.
- **Background scheduler** (`workmanager` periodic + one-shot flush,
  iOS BGAppRefresh): the 25 s foreground ticker exists (untested timer,
  tested pipeline); nothing refreshes in the background.
- **The W1 Day-0 spikes remain unrun** (sodium_libs on an Android
  emulator, home_widget hello-world). Consequence unchanged: the app has
  NEVER run on a device or emulator; platform glue has zero test coverage.
- **Docs spine**: since written. VISION.md, AGENTS.md, the `docs/` hub,
  ADRs 0001–0007 (0006 and 0007 describe this build) and
  `docs/security-model.md` (the threat model, rewritten 2026-09-28 against
  ADR-0006 and the code) all exist. BUILD-SPEC stays the fuller record of
  the design's whys.
- **`spec/vectors/*.json`** cross-language vector FILES (inherited from
  W2/W3). The cross-language pins that exist instead: the shared mailboxId
  vector asserted by both suites, the FakeRelay↔Go behavioral twinning,
  and now the live integration transcript — strictly stronger evidence
  than static vectors for the flows it covers, but not byte-pinned files.
- **No deployed relay.** Everything network-real happened on localhost.
- Local notifications still bind `NoopLocalNotifier` in production
  (tested diff logic, no flutter_local_notifications adapter); porch://
  OS-level deep links unwired (paste-the-code is the tested path); backup
  is a manual snapshot to a folder no automatic backup takes. All
  unchanged from W4, all still true. (The placeholder donation link was
  removed on 13 Nov: the publisher's rule is never to ask for donations.)

### Out of scope for v1, so a reader never mistakes absence for oversight

Per BUILD-SPEC §7: **no push** (v1.1, behind the compile-time `PushPort` —
`NoopPush` is the only implementation and a grep-test proves nothing
FCM-shaped is imported), **no passkey recovery** (v2 additive wrapper;
seed-first shipped), **single device** (one keypair, one phone; rosters key
on pubkey so multi-device stays possible later), **custom-scheme links +
paste-the-code only** (no https universal links), **iOS widget best-effort
at most** (nothing exists yet either way). Cut permanently on product
values, never returning: read receipts (the protocol cannot express them),
leave notifications (silent leave is sacred), telemetry of any kind
(on-device metrics only).

## Real and tested (app presentation — W4 package)

The PRESENTATION layer lives in `app/lib/presentation/` (tests
`app/test/presentation/`, 45 tests) plus the data services W3 left open
(`push_port.dart`, `notification_service.dart`, `metrics_service.dart`,
`backup_sink.dart` — 15 more data tests). Full app suite: **286 tests
green** via `flutter test`; `flutter analyze`: no issues. Everything below
runs against the W3 `FakeRelay` + in-memory stores through the SAME
Riverpod seams production bootstrap overrides — the wiring the tests
exercise is the wiring that ships.

- **Riverpod wiring** (`providers.dart`, flutter_riverpod 3.3.2 pinned
  exact): leaf providers (sodium, relay, key store, state store, clock,
  ticker flag, widget-mirror/notifier/push/backup-sink ports) are
  bootstrap-overridden; `sessionProvider` (null until an identity exists →
  onboarding owns the screen), one reactive `porchStateProvider`
  (load → mutate → save → reload), and `PorchActions` — one method per
  user intention. The refresh action runs **RefreshFeed → fulfill pending
  invites per group → local notification diff → reload**, tested
  end-to-end (a peer redeems an invite; my refresh fulfills it; a later
  refresh notifies exactly once when that friend turns available, and
  never re-fires for an unchanged feed).
- **A failed identity or state read**: riverpod 3's automatic retry is off (`noAutoRetry` on both async
  providers and at the root, `porchProviderScope`), and the root gate shows
  `OhErrorState` with Try again instead of onboarding when the keystore or
  the state file cannot be read. Before this, the gate sat on a spinner for
  about 38 s and then showed onboarding, whose restore saves over the
  unreadable file. Tested with failing keystore and state-store doubles
  (`read_failure_test.dart`, `root_scope_no_retry_test.dart`), in the
  harness, never on a phone.
- **A keystore that refuses at launch**: bootstrap no longer reads the
  state key or the saved relay URL before `runApp`. Those reads are
  `launchReadsProvider`, which the root gate watches first and shows like
  any other failed read, with Try again; `launchWiring` builds the state
  store and the relay endpoint from them. A read that throws mints no state
  key, and no state store opens without its key. The theme is still read
  before `runApp`; a refusal there opens in the default theme. Onboarding
  now shows its sentence for an Error (StateError, StateCorruptError) as
  well as an Exception. Tested in the harness, never on a phone
  (`read_failure_test.dart`, `error_states_test.dart`). Still before
  `runApp` and not covered: libsodium's init and the documents folder
  lookup.
- **Onboarding** (W4 acceptance): age gate (13+) → SILENT keygen →
  12-word reveal (the words on screen are decode-asserted against the
  stored entropy, and the 6 backup words beside them match the identity)
  → optional backup (the sink's blob is opened with the 6 backup words
  and matches; there is no PIN field) → display name → "My Porch" auto-created with self
  as admin. The relay call log is asserted **empty** across the whole
  flow — the name cannot have leaked because nothing was sent at all.
  Also tested: restore-from-12-words (deterministic identity, honest
  "identity-only — friends re-invite you" copy), restore-from-backup-file
  (fleet-fix item 10a) and mid-onboarding
  relaunch resuming past the age gate.
- **Home** (`home/`): the porch light On / Off control (one segmented
  control, same place in both states since 2026-09-28) → sheet with group
  multi-select (deselection tested to publish only to the rest), expiry
  30 m/1 h/2 h/4 h/custom-minutes, tag presets 🚶🧹🚗💻📖 + short custom
  tag; optimistic tap tested with the relay DEAD (light flips instantly,
  outbox queues); manual Off; feed rows with name, tag, countdown
  ("1 h left") and group names; tap-a-friend dialog with the roster's
  contact note; **typed-honesty staleness**: feed renders only through
  `FeedModel`, built solely from `PresenceSnapshot`s (fetchedAt required
  by type), and a >15-min-old snapshot renders "as of N min ago" while a
  fresh one shows no disclaimer — tested by going offline and advancing
  the clock. The 30-day feedback prompt appears when due and one tap
  dismisses it for another 30 days.
- **Groups** (`groups/`): create (relay call log asserted unchanged —
  client-side fact); detail with roster; invite mint dialog (porch://
  link + bare code, shown once); lifecycle **open → granted** driven by a
  real peer redeeming and my refresh fulfilling; **void → regenerate**
  (fresh token, old one dead, two rows tracked); admin REMOVE via member
  menu → a named confirm ("Remove Bob", `showOhConfirm`) → roster shrinks
  AND epoch advances to 2 (rotation
  proven from the UI path); TRANSFER_ADMIN (crown moves, epoch stays 1);
  **silent leave** — the confirm dialog promises "No one is notified",
  local state wipes, and nothing notification-shaped exists to render.
- **Join** (`join/`): paste-the-code (the primary tested path; the
  porch:// string parses identically) → honest "Waiting to be let in"
  state → Check now → group + roster delivered E2EE appear in the list.
  Typed failures tested: already-used invite ("ask for a fresh one") and
  garbage input, both human-readable, neither a crash.
- **Settings** (`settings/`): profile edit fans out as a signed PROFILE
  op — asserted by a PEER folding it into their roster on refresh; seed
  re-reveal matches the keystore and shows the 6 backup words; backup
  from settings (blob opens with this identity's 6 backup words, refuses
  others, contains groups);
  **notification opt-ins asserted OFF on the actual Switch widgets** on a
  fresh install, toggles persist locally; "Your Porch stats" renders the
  on-device numbers; "What leaves your device" names the residuals
  (ciphertext-only writes, the IP/timing residual, the never-leaves list)
  — grep-asserted in the test.
- **Data services** (host-VM, Flutter-free, purity-test covered):
  `notification_service.dart` — LocalNotifier port + diff rules
  (fresh install fires NOTHING; per-friend once per newly-available
  friend; per-group one digest; friend-level consumes the group count;
  self never fires; structurally no relay import, and an end-to-end test
  decrypts everything the relay holds to prove nothing pref-shaped ever
  left). `metrics_service.dart` — stats (total taps, active days,
  same-day-return days) + the 30-day dismissible prompt window.
  `push_port.dart` — `NoopPush`, the only v1 impl, with a source grep
  proving nothing FCM-shaped is imported anywhere in `lib/`.
  `backup_sink.dart` — `FileBackupSink` (fresh name per save, verbatim
  bytes) + recording test double.
- **Accessibility sweep + goldens** (house rule): Home (empty), Home
  (live feed + own light on) and GroupDetail at **320 dp, textScale 1–3**
  — overflow-free (three real overflow bugs found and fixed by the sweep:
  a fixed-height Available button, a Chip in a ListTile leading slot, and
  the invite dialog needing `scrollable`), pinned by 9 goldens
  (`test/presentation/goldens/`, regenerate with `--update-goldens`).
  Since 2026-09-28 the goldens render the real fleet fonts (canonical
  `test/flutter_test_config.dart`) and are tagged `golden`: CI compares
  their pixels only locally and still runs their overflow checks.
  No read-receipt affordance exists anywhere to assert absent.
- **`bootstrap.dart` + `main.dart`**: production DI — sodium_libs init,
  `FlutterSecureStorageSecretStore`, `EncryptedFileStateStore` in the app
  documents dir, `HttpRelayApi` against a compile-time
  `--dart-define=PORCH_RELAY_URL` (default deliberately `.invalid` — see
  gaps), `FileBackupSink`; Noop mirror/notifier/push per their W5/v1.1
  seams.

### W4 design decisions the next packages must know about

- **The §3.4 "notification diff" stage lives in the refresh ACTION**, not
  inside `sync_service.dart` (W3's tested pipeline is untouched):
  `PorchActions.refresh()` snapshots previous presence, runs
  `refreshFeed()`, fulfills pending invites (any-member fulfillment, so
  the 25 s poll doubles as the inviter-side handshake pump), then hands
  prev/next to `NotificationService`. W5's background refresh should call
  the same action, not `refreshFeed()` directly, or notifications will
  silently not fire from the background path.
- **`tickerEnabledProvider` gates BOTH fetch-on-open and the 25 s
  foreground poll** (bootstrap leaves it true; every test overrides it
  false and drives refresh explicitly). The periodic timer itself is
  therefore NOT under test — the pipeline it invokes is.
- **Onboarded ⇔ `profile.displayName` non-empty.** The RootGate resumes
  onboarding (past the age gate) when an identity exists but no name yet.
- **Regenerate on an already-voided row mints fresh** —
  `InviteRepo.regenerate` (void-then-mint) throws on re-void; the action
  branches on status. The UI splits "void" and "regenerate" into two taps
  on two row states.
- **testWidgets + FakeAsync zone gotcha** (cost an afternoon, documented
  in `test/domain/support/test_sodium.dart`): a Future first created
  inside one test's FakeAsync zone never resolves when awaited from
  another test's zone — completed-future callbacks schedule on the
  future's OWN zone. Widget tests therefore load libsodium fresh per test
  (`loadTestSodiumFresh`); the memoized loader stays for plain `test()`
  bodies. If a widget test ever hangs in `UiWorld` setup, start here.
- **Argon2id cost is provider-injected** (`backupLimitsProvider`): null =
  libsodium MODERATE in production; tests override to MIN so the backup
  path runs at test speed with the real KDF.

### Not claimed by W4 (honest gaps)

- **Never run on a device or emulator.** `bootstrap.dart`,
  `secure_storage_adapter.dart`, sodium_libs' bundled binaries and
  path_provider are platform glue exercised by zero tests (the W1
  Android-emulator spike debt still stands). Everything under them is
  host-tested; the glue itself is not.
- **No deployed relay + no UI-against-real-relayd run.** The default
  relay URL is a non-routable `.invalid` host on purpose; ~~W3's
  "twinned FakeRelay vs compiled Go relay" integration gap carries
  through W4 unchanged~~ — **partially superseded by W5**: the data stack
  (HttpRelayApi + repos + SyncService) is now proven against the compiled
  relayd on localhost (see the W5 section); the WIDGET layer against a
  real relay, and any deployed relay, remain unproven. **Home now says so
  (fleet-fix item 10b):** while the relay in effect is the `.invalid`
  placeholder, Home shows a "No relay set up" notice with a route to
  Settings, words a turned-on light as "on this phone only", and splits
  the empty feed so it no longer promises friends will appear; Settings'
  helper and "In effect" lines say the same. Tested in
  `test/presentation/relay_truth_test.dart`. The tap still records the
  light locally and queues it in the outbox, unchanged.
- **Local notifications don't actually pop yet**: the diff logic is real
  and tested, but production binds `NoopLocalNotifier` — the
  flutter_local_notifications adapter is unbuilt (W5-adjacent debt, named
  in bootstrap.dart).
- **porch:// OS-level deep linking is not wired** (no intent filter / no
  link-stream handler). The string parses when pasted — paste-the-code is
  the primary tested path, as specced — but tapping a link in a messenger
  will not open Porch yet.
- **Backup is a manual snapshot**: not opportunistically re-written on
  membership/epoch change (§3.1 step 7's "opportunistically re-written"
  is unimplemented — it would require retaining the derived key);
  ~~restore-from-backup-FILE has no UI~~ — **delivered by fleet-fix item
  10a**: the onboarding restore step offers "Restore from a backup file
  instead" (paste the file's text + the 6 backup words → `openBackup` →
  state saved, then identity; wrong words, a PIN, or a non-backup leave
  nothing behind and are
  explained in words; zero network), and Settings says where restoring
  happens. Tested in `test/presentation/restore_backup_test.dart`, on the
  host only. The sink writes into a `backups` folder no automatic backup
  takes (Android: `files/backups`, excluded in both backup rules files and
  pinned by `android_backup_rules_test.dart`; iOS and macOS: Application
  Support, which the system never clears, with the folder marked excluded
  from backup through a method channel before each write, and no write if
  that fails, Dart side pinned by `backup_folder_adapter_test.dart`, the
  Swift never compiled or run; none of it checked on a device), app-private and
  removed on uninstall; **since the follow-up,
  every backup ends in a "Backup saved" dialog that says so and offers
  "Share / save backup file"** — the system share sheet via share_plus
  12.0.2 (`lib/backup_share_adapter.dart`, the only importer), so the
  person can put a copy somewhere that lasts. Tested on the host: the
  action and dialogs against a recording port
  (`test/presentation/backup_share_test.dart`), and the adapter against a
  fake SharePlatform (`test/backup_share_adapter_test.dart`). The real
  share sheet has NEVER been opened on a device, and share_plus's Android
  build requirements are unverified here. There is no in-place
  identity swap from Settings — restore is a new-phone, first-screen act.
  A backup taken during onboarding predates the name step and "My Porch",
  so it holds identity but no groups — **the onboarding copy now says so,
  and Home offers a fresh backup (dismissible, "Not now" is permanent)
  once a group exists** (`test/presentation/fresh_backup_prompt_test.dart`).
  A person who skipped the onboarding backup now gets a **Finish setup**
  item on Home, below the light (fleet ruling 48): it stays until a backup
  exists or they say Not now, and Settings' backup row keeps saying "Not
  backed up on this phone yet" either way. Restoring from a backup file
  counts as backed up; restoring from the 12 words does not
  (`test/presentation/finish_setup_test.dart`).
- **The 25 s ticker and fetch-on-open are ungated-untested** (see design
  decisions): no test pumps 25 real seconds.
- Goldens render the real Nunito/Lora since 2026-09-28, but they are
  approved by eye on one machine: font rasterisation differs elsewhere,
  which is why CI does not compare their pixels.
- Background scheduler, widget bridge (home_widget), ~~rotation fan-out
  jitter~~ (**delivered by W5** — see its section), docs spine — the rest
  remain absent (see "Still absent after W5").

## Real and tested (app data layer — W3 package)

The DATA layer lives in `app/lib/data/` (tests `app/test/data/`, 96 tests).
Full app suite: **220 tests green** via `flutter test` (123 domain + 96 data
+ 1 scaffold widget test); `flutter analyze`: no issues. Like the domain,
the data layer is host-VM testable and FLUTTER-FREE — enforced by its own
source-grep test (`test/data/purity_test.dart`); the single allowed
exception is `secure_storage_adapter.dart` (see below).

- **`relay_api.dart` / `api_client.dart`** — the typed relay surface (§4)
  and its dart:io HTTP client, black-box tested against a real in-test
  `HttpServer`: all 12 endpoints' wire shapes (std-base64 blobs, base64url
  ids, `afterSeq`/`proof` params), one typed error per relay status, and
  two structural rules with tests: **no retries ever** (an ambiguous
  failure means delivery UNKNOWN; a retried POST could duplicate state) and
  **no identity material on `/v1/ch/*`** (the interface has no identity
  parameters; the emitted header set is asserted against an allowlist —
  user-agent suppressed, nothing cookie/authorization-shaped exists).
  Drain auth (`buildDrainAuth`) signs the relay's exact
  `porch-drain|{mailboxId}|{ts}` format, verified in-test against sodium.
- **`fake_relay.dart`** — in-memory `RelayApi` with the Go relay's EXACT
  semantics, unit-tested to the same behaviors the Go conformance suite
  pins: atomic one-time join (second → 410), first-use proof pinning,
  grant delete-after-retrieval, invite TTL death (expired == 404), mailbox
  depth cap 200, FULL drain verification (blake2b mailbox binding, ±300 s
  freshness, Ed25519, replay cache), presence native TTL on an injectable
  clock, per-channel monotonic seq, ring-of-8 unpinned eviction, pinned cap
  + own TTL, plus failure injection (`offline`, `callLog`, `wipeAll`).
- **`key_store.dart`** — the two §5.1 secrets behind a `SecretStore`
  abstraction (hex-encoded, size-validated, corrupt-reads-as-absent,
  generate-once state key, `wipe()`); `secure_storage_adapter.dart` binds
  it to `flutter_secure_storage 9.2.4` (pinned exact) with zero logic.
- **Start over with a new identity** (Settings,
  `presentation/settings/start_over_screen.dart`,
  `PorchActions.startOver`, `GroupRepo.leaveEveryGroup`). Leaves every
  group with someone else in it, each LEAVE posted at once while the
  identity exists; the remaining members' phones rotate the key when they
  fold it. Open invites are voided and their links burned first. A group
  the relay can't reach is named, and nothing is deleted unless the person
  chooses to go on. Then the backup files (the backups folder, and the
  share sheet's copies under the temporary folder), the state file and
  the keys go, and onboarding opens. Tested with the fake relay and
  in-memory stores (`test/presentation/start_over_test.dart`,
  `test/data/leave_every_group_test.dart`), and the file deletion on a
  real folder (`test/data/backup_sink_test.dart`). Not yet run on a
  device. Owed: rotation fan-out posts still held by their jitter when
  the person starts over are dropped with the outbox; the members then
  rely on the self-heal path. The web build's `deleteAll` (browser
  storage) runs only in a browser and has no test here.
- **`porch_state.dart` / `state_store.dart`** — the §5.2 model, exactly,
  round-trip tested; ONE versioned JSON document encrypted as ONE file
  (`state.v1.enc` = nonce ‖ XChaCha20-Poly1305, AD `porch/state/v1`, the
  version INSIDE the ciphertext), atomic tmp-write + rename (kill-mid-write
  leaves old state intact — tested), wrong-key/truncation → typed
  `StateCorruptError`, unknown version → `StateVersionError` or the
  migration hook. Disk bytes are asserted to contain no plaintext social
  graph. `InMemoryStateStore` round-trips real JSON on every save/load so
  fakes cannot hide serialization bugs.
- **`outbox.dart`** — write-behind queue (§3.4 optimistic outbox-first).
  Retry-safety is PROTOCOL-level, documented per op: presence = slot
  overwrite, bulletin = idempotent folds, mailbox = epoch-guarded adoption;
  invite create/join are foreground-only (one-time consumptions). Drain is
  FIFO: transient failures (unreachable/429/5xx) keep the entry + stop;
  permanent 4xx drops poison. Presence TTLs are recomputed at DELIVERY from
  absolute expiry — an event that expired while queued is never sent.
- **`group_repo.dart`** — groups as client-side facts (creation makes NO
  relay call — tested via call log); silent LEAVE (one sealed op + local
  wipe, offline-safe, nothing notification-shaped); admin REMOVE → the one
  shared `performRotation` (fan-out seals to every remaining member's
  mailbox, never the departed, dup on the OLD channel, local adoption);
  TRANSFER_ADMIN; PROFILE fan-out to every group. Own ops fold
  optimistically — safe because folds are idempotent when the echo returns.
- **`invite_repo.dart`** — §3.5 end-to-end over the FakeRelay with real
  crypto: mint (register id + pinned escrow; nothing persists if the relay
  call fails), redeem, fulfill (intro → JOIN announce → sealed grant; a
  vandal join blob voids the invite), complete (verify granter sig +
  roster provenance; tampered grant throws, never joins), void →
  regenerate (fresh token, old one dead), already-member resolution for
  stale escrows.
- **`sync_service.dart`** — RefreshFeed (§3.4 step 5) with the order the
  spec demands, asserted against the relay call log: outbox flush →
  bulletin fold by seq (grace channel first) → signed drain (strictly
  monotonic ts — Ed25519 is deterministic, same-second re-drains would trip
  the replay cache) → rotation adoption (validate → deterministic winner)
  → rekey re-grants → presence decode on the possibly-NEW channels →
  `PresenceSnapshot(fetchedAt: now)` → save → widget mirror. Scenario
  tests: two devices see each other's tags; join+publish visible in ONE
  refresh (fold-before-decode); LEAVE → admin rotates on fold, peer adopts
  via mailbox, everyone converges, re-refresh never re-rotates; REMOVE →
  peers adopt; grace-window straggler rendered; **wiped-store self-heal**
  (relay `wipeAll()` → REKEY_REQUEST → any-member re-grant → straggler
  converges); **escrow-orphan fulfillment** (inviter-admin leaves →
  successor admin ingests the pinned escrow and fulfills at the new epoch);
  offline refresh keeps the previous snapshot AND its previous `fetchedAt`
  (staleness must render, never a lie).
- **`widget_cache.dart`** — the §5.3 contract JSON builder (friends only,
  self excluded, cross-group dedupe keeping longest-remaining, top3,
  `fetchedAt` = OLDEST fetch shown) + `WidgetCacheMirror` port with
  `NoopWidgetCacheMirror` (the only W3 impl; the home_widget writer is W5).
- **`identity_service.dart`** — first-launch keygen persists entropy via
  `SecretStore`; deterministic restore from explicit entropy; refuses to
  overwrite an existing identity.

### W3 design decisions the next packages must know about

- **No `http` package.** The relay client is dart:io `HttpClient` directly:
  zero extra dependency, and the tests exercise real sockets against a real
  in-process server instead of a mocked client. The §2 sketch named `http`;
  this is an implementation detail, not an architecture change.
- **Grace-channel polling is cursor-split.** The current channel pages by
  `lastBulletinSeq`; the grace (old-epoch) channel is fetched from seq 0 —
  but roster ops fold only ABOVE the stored cursor (replaying a JOIN after
  a rotation would resurrect departed members; found by the idempotence
  test). Cursor-independent artifacts (ROTATION dups, ESCROWs,
  REKEY_REQUESTs) process from 0 — that is what lets a REKEY_REQUEST posted
  after total relay loss (seq counter reset) still be seen by rotated
  members. Total loss on the CURRENT channel remains the spec's accepted
  degradation (§5.4).
- **Outbox ids / fulfillment authority.** Escrow ingestion accepts pinned
  escrows from any (then-)roster member and `fulfillPending` may be run by
  any member holding the token — a slight widening of the spec's "any
  current admin", strictly more available and no weaker (any member can
  mint invites anyway; the JOIN fold requires a member signer).
- **Bob's redeemed-but-ungranted invite is in-memory only** (`JoinedInvite`).
  §5.2 has no field for it; if the app dies before `completeJoin`, the
  invite burns and the inviter regenerates — the universal recovery. W4
  should surface that plainly rather than pretend persistence.
- **The local tap keeps the old `fetchedAt`.** `fetchedAt` means "when
  relay data was fetched"; an offline tap upserts my own entry but does not
  move it. UIs must read own-status from the entry, not from snapshot age.

### Not claimed by W3 (still open for this layer)

- ~~`notification_service.dart`, `metrics_service.dart` (the 30-day prompt
  half), `push_port.dart` (NoopPush) — W4 scope per the module map~~ —
  **superseded: delivered and tested by the W4 package** (see its section);
  metrics RECORDING (publishes/firstAt/lastAt) already happened in
  presence_repo.
- `secure_storage_adapter.dart` is **not exercised by any test** — it is
  platform-channel glue and cannot run on the host VM; on-device smoke is
  still open after W4 and this line remains the record of it.
- No background scheduler — W5 was to wire the cadence and did not. The
  25 s foreground ticker exists (W4) but is itself untested (see the W4
  section).
- ~~Rotation fan-out **jitter (0–30 s) is still absent**~~ — **superseded:
  delivered and tested by the W5-finisher package** (see its section).
- `spec/vectors/*.json` remain absent (inherited W2 debt): the
  cross-language pins are still the mailboxId vector + the FakeRelay↔Go
  behavioral twinning, not byte-exact shared vector files.
- ~~The localhost integration harness against the COMPILED Go relay (spec
  W3's "integration" bullet) is **not built**~~ — **superseded: built by
  the W5-finisher package** (`test/data/relayd_integration_test.dart`,
  see its section). The W3-era caveat stands for the scenarios that only
  run against `FakeRelay` (time-travel suites: TTL death, staleness,
  grace windows, self-heal after a wiped store — the real relay runs on
  the wall clock, so those stay with the fake).

## Real and tested (app domain layer — W2 package)

Flutter app scaffolded at `app/` (`flutter create --org com.openhearth
--project-name porch_app .`). The DOMAIN layer lives in `app/lib/domain/` and
is **pure Dart** — no Flutter, no IO, no network imports (enforced by a
source-grep test, `test/domain/purity_test.dart`, mirroring the relay's
zero-logging grep). **123 tests green** via `flutter test test/domain` on the
Dart VM against the host's real libsodium (`SodiumSumoInit` + FFI —
no emulator, no plugin registry). `flutter analyze`: no issues.

- **Crypto deps pinned exact** (BUILD-SPEC §1.5): `sodium 3.4.6`,
  `sodium_libs 3.4.6+4` (4.x needs Dart ≥3.11; toolchain is 3.10.7 — newest
  compatible pinned), `crypto 3.0.7` (BIP39 SHA-256 checksum ONLY; a test
  asserts `package:crypto` appears solely in `mnemonic.dart`).
- **Canonical JSON** (`support/canonical_json.dart`): sorted keys, no
  whitespace, integer-only (doubles rejected), ASCII-only keys — the signing
  and AEAD input everywhere.
- **Mnemonic** (§3.1): 12-word BIP39 encode/decode of 16 B entropy; vendored
  canonical wordlist (sha256-verified); round-trip, determinism, published
  trezor vectors, checksum/word/count rejection, sloppy-input tolerance.
- **Identity** (§3.1): entropy → BLAKE2b root → crypto_kdf(PORCHSGN/PORCHBOX)
  → independent Ed25519 + X25519 seed keypairs; byte-identical determinism;
  **mailboxId pinned to the SAME vector as the Go relay's
  `TestDeriveMailboxIDVector`** (three independent implementations agree).
  Backup blob: Argon2id (MODERATE default, params ride the header) →
  XChaCha20-Poly1305 over {entropy, stateSnapshot}, under 6 backup words
  (66 bits) derived from the entropy, never picked by the person;
  round-trip, case and spaces tolerated, a PIN or anything but 6 list
  words refused before Argon2id, header cost above SENSITIVE or below the
  minimum refused before Argon2id, wrong-words and corrupt-blob clean
  failures, fresh salt/nonce per seal.
- **Keyring** (§3.2): channelId / slotId / pushTopic(dormant) derivations,
  all KDF-domain-separated and deterministic; epoch policy encrypt-newest /
  decrypt-last-2 / 7-day prune tested at exact boundaries; non-advancing
  epoch adoption rejected.
- **Envelope** (§3.3): sign-then-encrypt, AD = "porch/v1" ‖ channelId ‖
  epoch_le64; round-trip; grace-epoch decrypt; pruned-epoch drop; byte-flip,
  truncation, forged-sig, lying-epoch, non-JSON-plaintext all DROP silently.
- **Roster** (§3.7): JOIN/REMOVE/LEAVE/TRANSFER_ADMIN/PROFILE ops,
  seq-ordered deterministic fold, authority checks (non-admin REMOVE and
  non-member PROFILE rejected), idempotence (ops++ops == ops), and THE
  admin-succession rule (oldest joinedAt, tie = smallest sign_pk) implemented
  once and property-tested over 200 shuffled rosters with colliding
  timestamps. Silent leave is structural: a fold yields a roster and
  rejections — nothing notification-shaped exists.
- **Invite** (§3.5): token → inviteId/k_i/fetchProof/grantProof (keyed-hash
  domain separation), porch:// link + paste-code round-trip with embedded-id
  integrity check; secretbox join blob; sealed+signed grant blob (granter
  must sign the whole core and appear in the delivered roster); pinned
  ESCROW envelope with token↔inviteId binding (vandal cannot re-point an
  escrow); full transcript test (mint → join → fulfill → grant → Bob derives
  the same channelId and reads Alice's presence); orphaned-invite
  fulfillment by an admin via escrow; state machine open→joined→granted with
  void → regenerate (fresh token, terminal states enforced).
- **Rotation** (§3.6): departures (and only departures) trigger; rotator
  election delegates to the roster succession rule; per-member sealed
  bundles (never to the departed, never to self) + bulletin duplicate under
  the old epoch (departed member opens the outer envelope, finds no box);
  validation (expected-rotator for fresh e+1; any-member only under
  `selfHeal`); adoption winner = lowest bulletin seq, fallback
  admin-authored then smallest BLAKE2b(gk) — convergence property-tested
  over shuffled delivery orders; REKEY_REQUEST self-heal with
  roster-verified box key (mismatched or non-member requests refused).
- **Presence** (§3.4): encodeOn/encodeOff (off = 60 s signed tombstone), TTL
  = expiresAt−now capped at 14700 s, 1 KiB blob cap enforced;
  `PresenceSnapshot` **cannot be constructed without `fetchedAt`**
  (required, no default) with the >15 min staleness rule pinned at the
  boundary; feed fold verify → roster-check → dedupe (highest issuedAt) →
  drop expired/off/garbage/non-roster, order-independent.

### W2 design decisions the next packages must know about

- **Domain location:** per the task brief, the W2 domain lives in
  `app/lib/domain/` (tests `app/test/domain/`), not in a separate `core/`
  package as the module map sketched. It is pure Dart and structurally
  Flutter-free (grep-tested), so extracting it to `core/` later is `git mv`
  plus a pubspec — nothing imports Flutter. W3's integration harness should
  import it via `package:porch_app/domain/domain.dart`.
- **JSON byte conventions** (matches relay HONEST-STATUS): ids/proofs =
  base64url no-pad; keys/sigs/blobs inside JSON = standard base64.
- **Envelope inner format:** canonical `{"payload":{...},"sig":b64}`;
  channelId inside the AD is the utf8 of its base64url string form.
- **Grant/rotation bundles** share one signed-core shape
  (`{core, *SignPk, sig}` sealed in a crypto_box_seal); the granter/rotator
  signs the ENTIRE core (gk included), which is strictly stronger than the
  spec's "signed roster" minimum.
- **Self-heal is context-gated:** a re-grant of an epoch ≥ current+1 from a
  non-elected member validates ONLY with `selfHeal: true` (i.e. the client
  asked via REKEY_REQUEST or is restoring). Unsolicited bundles always face
  the strict expected-rotator check. The spec's "re-grants of an existing
  epoch may come from any roster member" is honored on exactly that path.
- **Backup blob container** is canonical JSON `{v, salt, ops, mem, nonce,
  ct}` (self-describing params) rather than the spec's loose `header ‖ body`
  concatenation sketch — same fields, unambiguous framing.

### Not claimed by W2 (still open for this layer)

- `spec/vectors/*.json` cross-language vector files are **still absent** —
  the only cross-language pin so far is the mailboxId vector shared with the
  relay's test suite. Envelope/invite/rotation transcripts should be dumped
  to `spec/vectors/` in W3 so Go asserts them too.
- The two-simulated-device `sim/` relay (`sim_relay.dart`, `sim_device.dart`)
  and `protocol.dart` (typed relay codecs + drain-signature construction)
  are **not built** — the W2 task brief scoped the domain modules; the
  transcript-level flows are covered by direct pure-function tests instead.
- ~~Rotation fan-out **jitter scheduling** (0–30 s) is W5 scope — not
  built.~~ — **superseded: delivered by the W5-finisher package.**
- `sodium_libs` is pinned and will init on-device via its bundled libsodium,
  but **no Android-emulator spike has been run** (W1 spike debt, inherited);
  domain tests prove the host-VM path only.
- ~~`main.dart` is still the flutter-create counter scaffold: no presentation
  layer exists.~~ ~~Nothing outside `domain/` is real yet~~ — **superseded
  twice: W3 delivered `app/lib/data/`, W4 delivered
  `app/lib/presentation/` + `bootstrap.dart`/`main.dart` (see their
  sections above).**

## Real and tested (relay)

- **All 12 relay endpoints** (BUILD-SPEC §4 rows 1–12) implemented in Go 1.25,
  stdlib `net/http` only, and exercised by black-box handler tests over the real
  router: invites (create / atomic one-time join / proof-gated fetch / grant /
  grant delete-after-retrieval), anonymous mailbox POST, stateless signed drain,
  presence post/get with native TTL slots, bulletin with server-assigned
  monotonic per-channel seq, ring-of-8 eviction (oldest unpinned only), pinned
  entries with own TTL + cap, `afterSeq` paging, healthz.
- **No session plane** — deliberately. The task brief inherited older wording
  ("challenge/response, TOFU register, sessions"); the frozen BUILD-SPEC §1.2
  removed all of it. Drain auth is one stateless Ed25519 signature over
  `porch-drain|{mailboxId}|{ts}` with ±300 s freshness and a 10-min replay
  cache; tested for accept, tamper, wrong key, wrong mailbox binding, stale and
  future timestamps, replay.
- **Storage behind one `Store` interface**; a single conformance suite runs
  against BOTH implementations:
  - `memstore` (injectable fake clock — the whole unit suite runs with zero
    services and zero sleeps), and
  - `redisstore` (real Redis 7, Lua-scripted atomic ops, raw-byte blob storage,
    minimal stdlib RESP client — no third-party Redis dependency), gated on
    `REDIS_URL`. **Both legs pass all 19 conformance subtests locally**
    (Redis 7-alpine via podman). CI without `REDIS_URL` runs the memstore leg
    and skips the Redis leg — that skip is visible, not silent.
  - The RESP client keeps a pool of at most 4 connections and closes any
    connection that returns an error, so a late reply after a timeout can
    never answer the next command; after a Redis restart only the command
    that finds a dead connection fails. If Redis fails every command for
    30 s, relayd exits 1 without a word and its supervisor restarts it.
    Tested against an in-process fake Redis on loopback
    (`internal/store/resp_test.go`, `resp_pool_test.go`,
    `cmd/relayd/main_test.go`), with `-race`; the real-Redis leg was not
    rerun (no `REDIS_URL` here).
- **Storage bounds against anonymous filling.** A mailbox its owner has
  never drained keeps posts 72 h, not 30 days; at most 20,000 such
  mailboxes and 20,000 channels may live at once (a write that would open
  one more is a 429; an owned mailbox is never refused); rate-limit
  buckets key an IPv6 address by its /64; compose and DEPLOY.md cap Redis
  at 512 MB with `noeviction`. Tested on the memory store and over HTTP,
  and **on 15 November 2026 against a real Redis 7** (the official
  `redis:7` image, 7.4.12, linux/amd64, pinned by the digest in
  docker-compose.yml), run on loopback with `--maxmemory 8mb
  --maxmemory-policy noeviction`, under `go test -race`: the Redis
  conformance leg (27 subtests, none skipped), the -OOM refusal, the
  drain order, the daily opening caps over HTTP, and a drain at the
  memory ceiling (`internal/store/redis_full_test.go`). At the ceiling
  both drains were refused and every blob came back once memory was
  freed. That run was on a development machine; no relay is deployed.
- **A full Redis refuses writes, by design.** No key is ever evicted (an
  evicting policy would drop the 10-minute drain replay entries first and
  make a captured drain replayable). The store names Redis's -OOM answer
  `ErrOutOfMemory`, and the relay answers new posts and drains with 507
  (Insufficient Storage), a 5xx, so the app's outbox keeps the post and
  tries again. A drain whose replay entry cannot be written is refused
  before any mail is touched. The caps bound counts, not bytes (20,000
  channels × 24 entries × 8 KiB is about 3.9 GB), so a relay under attack
  is expected to fill. Tested against a fake Redis that answers -OOM
  (`internal/store/oom_test.go`) and over HTTP
  (`internal/api/full_test.go`). The compose Redis and Caddy images are
  both pinned by digest, each to its linux/amd64 image.
- **A daily cap on openings per address.** One address (an IPv4 address
  or an IPv6 /64) may open 50 mailboxes and channels a day
  (`-opens-per-day`): a push that opens a never-drained mailbox, a write
  that opens a channel, and a drain that first makes a mailbox owned each
  count one. Past it, a write that would open something is a 429; writes
  to what exists never count, and a drain still returns the mail but does
  not make the mailbox owned (so making keys and draining their empty
  mailboxes no longer buys uncapped mailboxes). The count lives in
  relayd's memory beside the other rate buckets, never in Redis, and a
  bucket is dropped only once it has refilled to full, so idling does not
  reset a day (this also fixes the 50-a-day invite cap). A channel holds
  its place in the 20,000 for 72 h at most until a second slot writes to
  it; the first slot id is kept that long in `chw:{channel}`. A bulletin
  write names its writer by a bulletin writer id: keyed BLAKE2b-128 of
  `porch/bulletin-writer/v1` and the member's signing key, keyed by that
  epoch's group key (`deriveBulletinWriterId`, checked against a vector
  computed apart from libsodium). It shares nothing with the member's
  presence slot id, so the relay cannot tie a member's bulletins to their
  presence. A second member's bulletin confirms a channel as a second
  presence slot does, and a quiet group's channel no longer spends an
  opening on each write after 72 h. What the relay learns from it: which
  bulletins in one epoch share a writer, not who that writer is; the id
  changes with each rotation. Because the two ids differ, the relay sees a
  member who writes both presence and a bulletin as two writers, so that
  member confirms the channel alone. The relay needed no change for this:
  it checks only that the id is an id. The Redis script change from the
  earlier step is covered by the conformance suite, which runs on Redis
  only when `REDIS_URL` is set; it has not yet run there. One address with
  two ids can always confirm its own channels: the cap on openings is
  what bounds it. Tested on the memory store and over HTTP, and on Redis when
  `REDIS_URL` is set (`internal/api/opens_test.go`,
  `internal/store/conformance_test.go`).
- **Every write carries a TTL** — the `Store` interface has no TTL-less write
  path; conformance tests advance the clock and watch invites, presence,
  mailboxes, pins, rings, and replay entries actually die.
- **Atomicity under concurrency, race-detector clean** (`go test -race`):
  N concurrent joins → exactly one 204, rest 410; concurrent drains → returned
  == deleted, no duplicate delivery.
- **Privacy conformance tests** (CI-runnable, in `internal/api/privacy_test.go`):
  - stored-blob **byte-identity** on every write path, end-to-end through the
    HTTP layer, using NUL/high-byte/JSON-metacharacter-hostile blobs;
  - **zero-logging source grep** over the serving packages (`log.`, `slog.`,
    `fmt.Print*`, `os.Stderr` all forbidden in `internal/api` + `internal/store`);
  - **channel plane reads no identity**: `channels.go` provably (source-level)
    never touches headers, cookies, or the peer address; a behavioral test
    sends identity-shaped headers and asserts byte-identical responses;
  - error responses are bare status codes — bodies asserted empty;
  - unknown JSON fields rejected everywhere (nothing identity-shaped can ride in).
- **Rate limits + size caps** on every endpoint (per-IP token buckets,
  invite-create pinned at spec's ≤50/day/IP; caps 8 KiB join / 16 KiB grant /
  8 KiB mailbox / 1 KiB presence / 8 KiB bulletin; TTL bounds 72 h invite /
  14700 s presence / 259200 s pinned) — enforcement is tested, exact values are
  tunable constants.
- **`relayd` binary**: `-addr`, `-store=memory|redis`, `-redis-url`,
  `-trust-forwarded`; graceful shutdown on SIGINT/SIGTERM (verified);
  startup errors to stderr then exit 1 (verified); after startup, structural
  silence — net/http's internal logger is wired to `io.Discard`. Smoke-tested
  over real HTTP against both backends.
- **Compose stack** (`relay/docker-compose.yml` + `relay/ops/Caddyfile` +
  `relay/Dockerfile`):
  brought up for real (podman-compose, rootless) — TLS terminates at Caddy,
  HTTP 80 → 308 to HTTPS, presence round-trips byte-identical through
  caddy→relayd→redis, and `podman logs relayd` is **empty** afterward.
  Caddyfile validated with the real `caddy validate`; access-log output is
  explicitly `discard`. **Not true of the tree as it stands:** the compose
  file now sits in `relay/`, and its `build: ./relay` line is written for a
  compose file at the repo root, so from `relay/` it names a folder that
  does not exist. Found by reading, not by running. No bring-up from the
  present location is recorded here.
- `go test ./...` green with no external services; `go vet` clean.

## Design decisions the next packages must know about

- **Proof gating is first-use pinning.** The server never learns the invite
  token `t` (§3.5 registers only `inviteId`), so it holds no reference value
  to verify `fetchProof`/`grantProof` against. The relay therefore *pins* the
  first proof presented per gate (fetch/grant share the fetchProof pin; take
  pins grantProof separately) and requires equality afterward. Consequence: an
  attacker who somehow learns a bare `inviteId` could race a garbage proof to
  lock out or steal a blob — but every such blob is ciphertext (secretbox
  under `k_i`, or sealed to Bob's box_pk), so confidentiality never rests on
  the pin; the failure mode is denial, bounded by the 72 h TTL and the
  "void — regenerate" path. If W2/W3 wants cryptographic verification instead,
  the create body must additionally register proof hashes — that is a wire
  change and needs the ADR the spec demands.
- **Expired vs used invites:** records die at their real TTL (native expiry),
  so a *used* invite answers 410 for its whole lifetime; an *expired* one is
  indistinguishable from unknown → 404. The spec's "410 used/expired" is
  satisfiable only while the record exists; we chose honest TTL death over
  keeping tombstones forever.
- **Rate-limit state is in-memory per relay process** (spec's module map says
  in-memory; the §5.4 table also sketches an `rl:{ip}` Redis key — we followed
  the module map). Restart resets buckets; fine for a single-instance deploy,
  revisit only if the relay ever scales horizontally.
- **JSON encodings:** ids (`inviteId`, `mailboxId`, `channelId`, `slotId`,
  proofs) are base64url-no-padding strings; `blob`/`pubkey`/`sig` fields are
  standard base64 (Go `encoding/json` `[]byte` convention). `expiresAt`/`ts`
  are unix seconds. W2's `protocol.dart` must match this.
- **mailboxId derivation vector:** `deriveMailboxID` (BLAKE2b-256 over
  `"porch/mbox/v1" ‖ sign_pk`, base64url) is pinned in `sigauth_test.go`
  against a vector computed with an independent implementation (Python
  `hashlib.blake2b`). The cross-language `spec/vectors/kdf_vectors.json` file
  is still the core package's job (see below).

## Not built yet (other packages' scope — nothing here is claimed)

- `core/` (pure-Dart `porch_core`): mnemonic, identity, keyring, envelope,
  roster, invite, rotation, snapshot — **now delivered by the W2 package in
  `app/lib/domain/` instead** (see the W2 section above); `protocol.dart` and
  `sim/` remain absent.
- `spec/vectors/*` cross-language test vectors — **absent** (core seeds them;
  the relay's Go-side vector assertions will consume them in W3).
- ~~W3 integration harness (two clients over localhost against the compiled
  relay) — **still absent**~~ — **superseded: delivered by the W5-finisher
  package** (see its section). The wiped-store self-heal specifically is
  still `FakeRelay`-only (needs fake-clock time travel).
- ~~`app/` Flutter presentation + bootstrap~~ — **superseded: delivered by
  the W4 package** (see its section). Widget bridge + background
  scheduler — **W5, absent**. The data layer beneath them is real (W3).
- Day-0 spikes (`sodium` on Dart VM, `home_widget` hello-world) — **not run**;
  they belong to the core/app packages and their pass/fail notes must land
  here before any dependent claim.
- ~~`ops/porchd.service`, `ops/DEPLOY.md`, README~~ — **superseded:
  delivered by the W5-finisher package** (now under `relay/ops/`). `docs/`
  spine, ADRs 0001–0007, VISION, AGENTS.md — **since written** (see "Still
  absent after W5").

## Known residuals & environment notes (relay)

- **IP/timing correlation** at the relay remains, as the PRD/spec accept:
  a live observer sees which IPs poll which channelIds. Nothing is stored.
- Caddy's *process* stream (stderr) carries operational errors (cert renewal,
  binds) — never request data; access logs are discarded by config.
- The Redis conformance leg and the compose stack were verified on this
  machine with rootless podman; CI wiring (e.g. a Redis service container) is
  future work and until then CI covers the memstore leg only.
- `docker-compose.yml` publishes 80/443; rootless local runs need a port
  override (documented here because it will bite the next person too).

---

## Post-landing security review (2026-07-10)

Two verified MAJOR findings from the competition's adversarial verify pass were
fixed TDD-first and re-verified (see the two `fix(...)` commits). Residuals that
remain, stated plainly:

- **Rate-limit XFF trust is single-hop, single-header.** The fix keys on the
  LAST `X-Forwarded-For` hop (correct for the frozen single-Caddy topology,
  which appends the real client IP as that hop). Two residuals: (a) a second
  trusted proxy layer (a CDN in front of Caddy) would collapse per-client limits
  to per-edge limits — safe/fail-closed but coarse; (b) `router.go` reads only
  the first XFF *header line*, so a terminator that adds its hop as a separate
  header line (HAProxy `option forwardfor` style) rather than joining one line
  (Caddy/nginx) would leave an attacker line as the key. Neither applies to the
  shipped Caddyfile; both would need an explicit trusted-hop/CIDR config if the
  topology changes.
- **A benign LEAVE does not void outstanding invites** (only a hostile REMOVE
  does) — intentional, so the PRD's escrow-rescue of a leaver's orphaned invite
  still works; a departing member is not an adversary in the threat model.
- **The off-device backup blob holds the social graph.** It contains the
  identity entropy AND the full state snapshot (every group key, the roster,
  contact notes), protected by the 6 backup words via Argon2id. This is the
  PRD-specified design (the backup exists to restore everything). Since
  November 2026 the person no longer picks a PIN: the words carry 66 bits,
  so a stolen file alone is out of reach of guessing. The residual is that
  a stolen file + the stolen 6 words = full compromise of that user's
  graph, and that the words are derived from the identity, so whoever
  holds the 12 words can also make the 6.
- **The "Bob joined" passive join announcement (PRD Core Feature 4) is not
  surfaced** in the group detail UI. Feature gap, not a security issue — the
  roster updates, but the one-line "someone joined" notice on next open is
  unbuilt.

## Android build (2026-07-10)

The client now **builds** for Android: `flutter build apk --release --split-per-abi
--target-platform android-arm64` → an 18 MB arm64 APK (the `ground-up-preview`
release), with `sodium_libs` bundling libsodium 1.0.20. This closes the earlier
"never built / no Android sodium spike" debt at *compile+package* level. It does
**not** close runtime: the app has still never been launched, so `sodium_libs`
init, `flutter_secure_storage`, `path_provider`, and the widget all remain
device-untested. **That APK could not have reached a relay either:** its
merged release manifest declares no `INTERNET` permission (Flutter adds it
only to the debug and profile manifests). Fixed 2026-09-28 in
`app/android/app/src/main/AndroidManifest.xml`, pinned by fleet
conformance C4 (`app/test/fleet_conformance_test.dart`); no APK has been
built since. (The grafted widget provider was rebuilt on the framework
`AppWidgetProvider` because the ground-up client, unlike the pre-competition one,
does not depend on `home_widget`.)
