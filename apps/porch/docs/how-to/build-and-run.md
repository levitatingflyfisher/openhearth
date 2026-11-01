# How-to: build & run

Porch is two codebases: a Go relay (`relay/`) and a Flutter app (`app/`). They build
independently. Porch is **pre-release**: both run and test on a development machine,
the app has never run on a phone, and no relay is deployed
([feature status](../reference/feature-status.md)).

## The relay (`relay/`)

Needs Go 1.25+ (`relay/go.mod`).

```bash
cd relay
go vet ./...
go test ./...              # one visible skip: the Redis conformance leg needs REDIS_URL
go run ./cmd/relayd        # in-memory store on :8080; prints nothing while serving
curl -i http://127.0.0.1:8080/v1/healthz     # → 200
go run ./cmd/relayd -h     # flags; --version prints the build version
```

To run the store tests against a real Redis 7, start one with a small
`--maxmemory` (1 to 64 MB) and `--maxmemory-policy noeviction`, then run
`REDIS_URL=redis://127.0.0.1:6379 go test -race -p 1 -count=1 ./...`.
Keep `-p 1`: the store and api packages flush the same Redis, so packages
run side by side would wipe each other's data mid-test.

For relayd + Redis + Caddy (TLS) together, `relay/docker-compose.yml` is the stack; the
walkthrough, flags and exit codes are in [DEPLOY.md](../../relay/ops/DEPLOY.md).

## The app (`app/`)

Needs the Flutter SDK that satisfies `app/pubspec.yaml` (Dart >= 3.10.7), and libsodium
on the host for the tests (the domain tests run on the Dart VM against it; point
`PORCH_LIBSODIUM=/path/to/libsodium.so` at it if it is not found).

`apps/porch/app` resolves shared packages through the OpenHearth root Dart Pub Workspace
(`resolution: workspace`). Run `flutter pub get` once from the monorepo root before
analyzing or testing inside `apps/porch/app`:

```bash
# From the monorepo root:
flutter pub get

# Inside apps/porch/app:
cd apps/porch/app
flutter analyze
flutter test --no-pub -j 1 test/presentation/home_test.dart   # one file at a time
flutter test --no-pub -j 1                                    # the whole suite
```

`test/data/relayd_integration_test.dart` compiles `../relay` with `go` and drives two
real clients through it; without `go` on the PATH it skips visibly.

The relay URL is set at runtime in Settings → Relay server, or at build time with
`--dart-define=PORCH_RELAY_URL=https://your.relay`. Without either, the app uses a
placeholder that can never resolve and stays on one phone; Home says so.

`flutter run` on a device or emulator has not been done for this codebase yet; expect
the first run to find platform problems the host tests cannot.

### The app's own address and the move page

Porch on the web moves to its own address, `porch.familyflourishing.org`
(owner ruling, 15 Nov 2026), once that domain is live and only after the
security fixes for a public web build. `app/web/CNAME` names it, and the
build copies it to the site root. Two web builds then come from the same
code, run in `app/`:

```bash
# The app at its own address
flutter build web --release --base-href /

# The move page, at levitatingflyfisher.github.io/move/porch/
flutter build web --release --base-href /move/porch/ --dart-define=OH_MOVE_PAGE=true
```

The move page stays up for good, because data saved at the old address can
only be read there. It reads the identity and groups without making a state
key, and seals and hands over the backup file without saving a copy or
changing a setting (`app/lib/move/move_page.dart`). The new address restores
it from the file's text and the 6 backup words. It goes in the landing repo
under `move/porch/`, without the `CNAME` file.
