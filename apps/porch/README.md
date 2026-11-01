# Porch

**The open door for your friend group.** Tap the porch light on; the close friends who
already know your door see that you're available, and reach you the way they always do.

> **Porch is a presence signal, not a communication channel.** You turn your porch light *On*; your
> circle sees the light is on; they call you on Signal, FaceTime, or the phone — whatever
> you already use. Porch never carries the conversation. It only says the light is on.

No chat. No calling infrastructure. No social network. No feed. No location. No accounts,
no email, no phone number, no PII. A local-first, end-to-end-encrypted, FLOSS app for the
people you already love.

> [!WARNING]
> **Porch is pre-release.** The blind Go relay, the end-to-end encryption, and the app's
> screens are built and tested on the host, and a test drives two real clients through
> the compiled relay. But the app has **never run on a phone or emulator**, the
> homescreen widget and background refresh are not built, and **no public relay is
> deployed**: out of the box the app points at a placeholder and works on one phone only
> until you run a relay and enter its URL in Settings. The ledger of what is real is
> **[HONEST-STATUS.md](HONEST-STATUS.md)**; read it before adopting or building on this.

## What's here

Porch lives at `apps/porch/` inside the OpenHearth monorepo and contains two codebases:

- **`app/`** - a Flutter app (iOS + Android + Web). A porch light *On / Off* control, a small feed of
  who's available in your groups, and a homescreen **widget** as the primary, ambient
  surface. *(Today: onboarding, Home, groups, invites, join and settings screens, tested on
  the host; the widget is not built yet.)*
- **`relay/`** - `relayd`, a minimal **Go presence relay**: a blind relay, not a
  backend-as-a-service. No accounts, no login, no PII: access is by knowing an unguessable
  address, and the one signed request (ed25519) is a device draining its own mailbox.
  End-to-end-encrypted blobs only, presence that expires on its own, and **zero logs**.
  In-memory storage by default, Redis by flag.

## Quickstart

### Run the relay (`apps/porch/relay/`)

```bash
cd apps/porch/relay
go vet ./...
go test -race -p 1 ./...      # one visible skip: the Redis leg needs REDIS_URL
go run ./cmd/relayd           # in-memory store on :8080; prints nothing while serving
curl http://127.0.0.1:8080/v1/healthz    # -> 200
go run ./cmd/relayd -h        # flags
```

For Redis and TLS, `relay/docker-compose.yml` runs relayd + Redis + Caddy; the walkthrough
is **[relay/ops/DEPLOY.md](relay/ops/DEPLOY.md)**. No public relay is deployed; the
Hetzner walkthrough has not been run against a live machine.

### Run the app (`apps/porch/app/`)

`apps/porch/app` participates in the root Dart Pub Workspace (`resolution: workspace`).
Resolve workspace dependencies once from the monorepo root, then run tests inside `apps/porch/app`:

```bash
# From the OpenHearth monorepo root:
flutter pub get

# Then inside apps/porch/app:
cd apps/porch/app
flutter analyze
flutter test --no-pub -j 1    # host tests; one of them compiles and boots relayd
flutter run                   # untested on a device so far
```

Point the app at your relay in Settings -> Relay server, or at build time with
`--dart-define=PORCH_RELAY_URL=https://your.relay`.

## See the docs

Start with the **[documentation hub](docs/README.md)** — it's organized on the
[Diátaxis](https://diataxis.fr/) model (tutorials · how-to · reference · explanation).

- **[Vision](VISION.md)** — the one idea, the invariants, the honest scorecard.
- **[Security & privacy model](docs/security-model.md)** — the threat model, E2E design,
  and exactly what the server can and cannot see. The heart of Porch.
- **[Architecture overview](docs/architecture/OVERVIEW.md)** — how the app and relay fit together.
- **[Concepts](docs/concepts.md)** · **[Limitations](docs/limitations.md)** ·
  **[Feature status](docs/reference/feature-status.md)** · **[ADRs](docs/adr/)**.
- Working in the code? **[AGENTS.md](AGENTS.md)**.

## Ethos

Porch is part of **OpenHearth** — free, local-first, privacy-respecting tools for
households and the people in them. Local-first, no ads, no tracking, no data sales,
audited crypto only, open by default. The code is a recipe worth sharing.

## License

MIT — see [LICENSE](LICENSE). Porch is FLOSS so it can be audited and self-hosted,
because trust in a privacy tool comes from being able to check it.
