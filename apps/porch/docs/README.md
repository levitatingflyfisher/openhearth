# Documentation

Organized on the [Diátaxis](https://diataxis.fr/) model — four kinds of docs for four
different needs. Find what you need by *what you're trying to do*, not by guessing a
filename.

| I want to… | I need | Go to |
|---|---|---|
| **learn by doing** | a Tutorial | [Tutorials](#tutorials) |
| **accomplish a specific task** | a How-to guide | [How-to guides](#how-to-guides) |
| **look up exact details** | Reference | [Reference](#reference) |
| **understand why** | Explanation | [Explanation](#explanation) |

New here? Porch is **pre-release** — start with the [README](../README.md) and the honest
scorecard in [VISION.md](../VISION.md) so you know what's built before you dig in.

---

## Tutorials
*Learning-oriented — take me by the hand through my first success.*

*Gap (contributions welcome):* there is no hand-held "turn your light on" tutorial yet;
the app has never run on a phone and no relay is deployed. The closest first success is
running the relay and the test suites: [How-to: build & run](how-to/build-and-run.md).

## How-to guides
*Task-oriented — how do I accomplish X (assumes you know the basics)?*

- **[Build & run](how-to/build-and-run.md)** — the two build stories: the Go relay and
  the Flutter app.
- **[Deploy the relay](how-to/deploy-relay.md)** — compose or systemd, flags, exit codes.
- Working *in* the repo (agents + humans): **[AGENTS.md](../AGENTS.md)**.

## Reference
*Information-oriented — tell me exactly, precisely, completely.*

- **[Feature status](reference/feature-status.md)** — what is built, scaffolded, or
  designed. Read this before assuming a feature exists.
- **[Relay API](reference/server-api.md)** — the twelve routes, their bodies, limits
  and status codes.
- Spike results: **[Passkey / recovery spike](PASSKEY_SPIKE.md)** ·
  **[Widget spike](WIDGET_SPIKE.md)**.

## Explanation
*Understanding-oriented — help me understand the ideas and the why.*

- **[Vision](../VISION.md)** — the one idea, the invariants, the honest scorecard.
- **[Architecture overview](architecture/OVERVIEW.md)** — the app ↔ relay picture + diagrams.
- **[Security & privacy model](security-model.md)** — the threat model, the E2E design,
  and exactly what leaves the device. The heart of Porch.
- **[Personas](explanation/personas.md)**: who agents play when they test the UI, with scenarios.
- **[Concepts](concepts.md)** — presence vs. communication, the porch-light metaphor,
  groups, availability TTL.
- **[Architecture Decision Records](adr/)** — why each load-bearing choice was made.
- **[Limitations](limitations.md)** — read before adopting. What it does *not* do, and
  what isn't built yet.
