# OpenHearth

Local-first, privacy-respecting, MIT-licensed household apps, shared Dart/Flutter libraries, native sync primitives, and companion web apps in one canonical monorepo.

No ads. No telemetry. No mandatory cloud accounts. Primary data stays on your device, with encrypted backups and optional self-hosted sync where needed.

## Repository Map

### `apps/` (14 Flutter apps)

| Path | App | What it is |
|---|---|---|
| [`apps/Bulwark`](apps/Bulwark/) | Bulwark | Local-first health-habit operating system. |
| [`apps/Furrow`](apps/Furrow/) | Furrow | Local-first daily-virtue and habit tracker. |
| [`apps/Glass`](apps/Glass/) | WeatherGlass | Calm, local-first FLOSS weather app. |
| [`apps/Hatch`](apps/Hatch/) | Hatch | Local-first times-tables mastery app for kids. |
| [`apps/Lilt`](apps/Lilt/) | Lilt | Local-first baby name ranking for couples. |
| [`apps/Lullaby`](apps/Lullaby/) | Lullaby | FLOSS baby tracker for exhausted parents. |
| [`apps/Mantle`](apps/Mantle/) | Mantle | Discover a family's shared aesthetic, local-first and account-free. |
| [`apps/Peckish`](apps/Peckish/) | Peckish | Family recipe box, weekly dinner plan, and grocery list. |
| [`apps/porch`](apps/porch/) | Porch | Close-friend presence signal (Flutter `app/` + blind Go `relay/`). Pre-release; see [`apps/porch/HONEST-STATUS.md`](apps/porch/HONEST-STATUS.md). |
| [`apps/PunctumTemporis`](apps/PunctumTemporis/) | Punctum Temporis | Capture one second of video every day, local-first. |
| [`apps/Reckon`](apps/Reckon/) | Reckon | Local-first personal decision journal with an on-device model. |
| [`apps/StillLife`](apps/StillLife/) | Still Life | Offline-first home inventory management system. |
| [`apps/Sundial`](apps/Sundial/) | Sundial | Local-first outdoor time tracker. |
| [`apps/Trellis`](apps/Trellis/) | Trellis | Local-first reader, podcast inbox, and spaced-repetition study app. |

### `packages/` (7 shared Dart/Flutter libraries)

| Path | Package | What it is |
|---|---|---|
| [`packages/domovoi`](packages/domovoi/) | `domovoi` | Model-agnostic family cognition and discernment library. |
| [`packages/elo_engine`](packages/elo_engine/) | `elo_engine` | Pure-Dart pairwise ranking engine (ELO, Glicko-2, and peers). |
| [`packages/ohStyle`](packages/ohStyle/) | `openhearth_design` | Design tokens, typography, tri-theme (`light`/`hearthDark`/`night`), and shared widgets. |
| [`packages/sanctuary_auth_core`](packages/sanctuary_auth_core/) | `sanctuary_auth_core` | Recovery words, keys, secure storage, and sync client primitives. |
| [`packages/sanctuary_backup_ui`](packages/sanctuary_backup_ui/) | `sanctuary_backup_ui` | Drop-in encrypted `.ohbk` backup and restore UI. |
| [`packages/oh_fleet_conformance`](packages/oh_fleet_conformance/) | `oh_fleet_conformance` | Dev-dependency test harness verifying fleet privacy, a11y, and hygiene invariants. |
| [`packages/oh_release_kit`](packages/oh_release_kit/) | `oh_release_kit` | Pure-Dart CLI for release checks, leak scans, web builds, APKs, and clean exports. |

### `native/`

| Path | What it is |
|---|---|
| [`native/hearthSync`](native/hearthSync/) | Pure Rust sync kernel (`hearth_sync_kernel`) plus Rust (`relay/`) and Go (`go-relay/`) reference relays checked against shared conformance vectors. |

### `web/`

| Path | What it is |
|---|---|
| [`web/NightGlass`](web/NightGlass/) | Calm, local-first stargazing companion for family camping trips. |
| [`web/Parlour`](web/Parlour/) | Pass-and-play family games cupboard as a single-file PWA. |
| [`web/ohSite`](web/ohSite/) | OpenHearth app hub and web landing site. |

### `docs/` and `scripts/`

- [`docs/specs/`](docs/specs/) - Cross-fleet technical specifications (including `BACKUP_RETENTION_SPEC.md`).
- [`scripts/monorepo-monthly-fold.sh`](scripts/monorepo-monthly-fold.sh) - Per-component midnight-UTC monthly history fold tool (dry-run by default).
- [`scripts/retire-legacy-repos.sh`](scripts/retire-legacy-repos.sh) - Reviewable dry-run script for retiring old standalone per-app/per-library GitHub repos once the monorepo cutover is verified.

## Workspace Quickstart

All 38 Dart and Flutter packages resolve through the root Dart Pub Workspace ([`pubspec.yaml`](pubspec.yaml)):

```bash
# Resolve workspace dependencies once from the repo root
flutter pub get

# Analyze and test a shared package
(cd packages/ohStyle/openhearth_design && flutter analyze && flutter test --no-pub -j 1)

# Test an app (sequential -j 1 keeps memory usage low)
(cd apps/porch/app && flutter test --no-pub -j 1)

# Test the Porch blind Go relay (Redis leg skips when REDIS_URL is unset)
(cd apps/porch/relay && go vet ./... && go test -race -p 1 ./...)
```

## Public History Policy (Per-App Midnight-UTC Monthly Fold)

Real commit timestamps leak timezone, sleep schedule, and daily work rhythm. Public history on this repository therefore follows a strict monthly fold policy:

- **Timestamp:** every published commit carries author and committer date `YYYY-MM-01T00:00:00Z` (midnight UTC on the 1st of the month).
- **Author identity:** `OpenHearth Development <90985475+levitatingflyfisher@users.noreply.github.com>`.
- **Per-component commits:** inside each month, the workspace/shared base and each touched app or component get separate linear commits on `YYYY-MM-01T00:00:00Z` so readers can inspect changes per app without exposing real commit cadence.
- **Exact trees and local backups:** [`scripts/monorepo-monthly-fold.sh`](scripts/monorepo-monthly-fold.sh) creates a full local `git bundle` backup before touching any ref, runs leak and attribution audits, builds the folded commit chain with `git commit-tree`, and asserts `git diff --quiet HEAD <new_tip>` (100% byte-identical tree) before any ref update.

```bash
# Preview the monthly fold (dry-run by default; touches no refs, pushes nothing)
./scripts/monorepo-monthly-fold.sh --month 2026-11

# Execute rewrite locally only (no push)
./scripts/monorepo-monthly-fold.sh --month 2026-11 --execute --no-push
```

## License

MIT. See [LICENSE](LICENSE). Each app and package also ships its own `LICENSE` file.
