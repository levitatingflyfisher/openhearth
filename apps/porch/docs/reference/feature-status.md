# Feature status

Per-component status, written from the code. Porch is **pre-release**. The detailed
ledger, with what each part was tested against, is [HONEST-STATUS.md](../../HONEST-STATUS.md);
if this page and that one disagree, that one is newer.

- **Built** — real code with host tests.
- **Spike** — code exists but is not wired to the app.
- **Absent** — not in the tree.

Nothing below has run on a phone or emulator. "Built" means built and tested on a
development machine.

## Relay (`relay/`) — Go

| Component | Status | Where |
|---|---|---|
| `relayd` binary, flags, exit codes, `--version` | **Built** | `cmd/relayd/main.go`, `main_test.go` |
| Invite, mailbox, presence and bulletin endpoints (12 routes) | **Built** | `internal/api/`; see [server-api](server-api.md) |
| Signed mailbox drain + replay cache | **Built** | `internal/api/sigauth.go` |
| Per-IP rate limits, size caps, no-log guarantee | **Built** | `ratelimit.go`, `router.go`, `privacy_test.go` |
| In-memory and Redis stores, one conformance suite | **Built** | `internal/store/` (Redis leg needs `REDIS_URL`) |
| Compose stack (relayd + Redis + Caddy), systemd unit | **Built**, never deployed | `docker-compose.yml`, `ops/` |
| A deployed public relay | **Absent** | the app ships a `.invalid` placeholder URL |

## App (`app/`) — Flutter

| Component | Status | Where |
|---|---|---|
| Client crypto: BIP39 identity, group keys with epoch rotation, envelopes, rosters | **Built** | `lib/domain/` (libsodium via `sodium` / `sodium_libs`) |
| HTTP relay client, repositories, outbox, sync | **Built** | `lib/data/`; proven against the compiled relay by `test/data/relayd_integration_test.dart` |
| Onboarding: age gate, silent keygen, 12 words, optional backup, name | **Built** | `lib/presentation/onboarding/` |
| Restore from 12 words, or from a pasted backup file + its 6 backup words | **Built** | onboarding restore step |
| Home: porch light On / Off control, Available sheet, expiry, tag, feed, staleness line, no-relay notice, Finish setup item for a skipped backup | **Built** | `lib/presentation/home/` |
| Groups, invites, join by pasted code, remove, transfer admin, silent leave | **Built** | `lib/presentation/groups/`, `join/` |
| Settings: profile, relay URL, recovery words, backup + share sheet, stats, theme (light / dark / follow the phone), start over with a new identity | **Built** | `lib/presentation/settings/` |
| Local notifications | **Spike** | diff logic tested; production binds a no-op notifier |
| Homescreen widget | **Spike** | `android/.../PorchWidgetProvider.kt` exists; nothing writes presence to it (`home_widget` is not a dependency). The iOS spike was removed |
| Background refresh, push | **Absent** | foreground 25 s poll only; push is out of scope for v1 |
| `porch://` OS deep links | **Absent** | paste the code instead |
| Passkey recovery | **Absent** | seed-first by decision ([ADR-0004](../adr/0004-seed-backup-recovery-over-passkeys.md)) |

## Dependencies

App runtime dependencies are in `app/pubspec.yaml`; the crypto ones (`sodium`,
`sodium_libs`, `crypto`) are pinned exact. The relay depends on the Go standard library and
`golang.org/x/crypto` only (`relay/go.mod`); it speaks to Redis through its own small
RESP client (`internal/store/resp.go`).
