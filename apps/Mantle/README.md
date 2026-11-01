# Mantle

*Discover your family's shared aesthetic — and keep it.*

> **Vision:** A household has a felt-but-unspoken aesthetic — a way it wants its
> home, its clothes, its spaces to *feel* — that no one can quite name. Mantle
> surfaces it from the family's own choices (not a quiz), and turns it into a
> printable **House Charter** you can keep. Local-first, account-free, no taste
> scores. See **[VISION.md](VISION.md)**.

Mantle is a free, local-first Flutter app for households. Everyone sits down
together around one device and answers a stream of two-second questions —
*"which of these is more **us**?"* — across three domains (architecture,
tailoring, interiors). When everyone's done, Mantle merges the choices and
reveals:

- **The Spine** — where the family genuinely converges: your shared favourites.
- **Where the House argues** — the items you lovingly disagree on.
- **Named through-lines** — the cross-domain threads that run through what you
  love (e.g. *the charged gap*, *material honesty*).

From there you name your House, write an optional motto, and export a one-page
**Charter** to PDF. The reveal is an heirloom the family authors — the app never
declares your taste for you.

## How a sitting goes

1. **Gather** — add 2–5 members (a label and a colour; no accounts).
2. **The round** — pass the device around. Each person ranks the same fixed deck
   of 24 images via quick head-to-head pairs, per domain. No peeking at anyone's
   results mid-sitting.
3. **The reveal** — after everyone's finished, the merged Spine / Contested /
   through-lines appear.
4. **The Charter** — name your House, add a motto, print it.
5. **Explore (solo, any time)** — optional depth: **Read** (a real vocabulary),
   **Spot** (train your eye), **Map** (see your through-lines). Never scored.

A solo user can Read / Spot / Map any time, but the House reveal needs **≥ 2
rankers** to mean anything — that's stated, not implied.

## Learn your style (the menswear tutor)

Home also has a **Learn your style** card. It opens a menswear tutor that is
separate from the House round and its three domains. It has four parts:

- **Learn the names**: term cards with a drawn plate, a gloss, "What you
  notice" and "The tell". "Add to my lexicon" saves the term for the chosen
  member. A two-plate **Quiz** ("Spot the difference") sits beside it.
- **Find your lean**: 24 head-to-head picks ("Which draws you?") over a fixed
  pool of garments, outerwear and footwear.
- **Your Field Guide**: where those picks sit on three axes (relaxed to
  structured, graphic to muted, directional to classic), the nearest named look
  once there are enough picks, and the words in your lexicon.
- **Your Wardrobe Charter**: two or more members each do a lean round on the one
  device, with a pass-the-phone screen between them. The result shows a shared
  Spine, a "Your house leans ..." line and the contested pieces. It is a screen
  only. It is not saved as a House Charter and has no name, motto or PDF export.

## Quickstart

```bash
flutter pub get
flutter run           # a device or emulator; also builds for web/desktop
flutter test          # the full suite
flutter analyze lib test
```

Flutter SDK `>=3.5.0 <4.0.0`. Mantle path-depends on sibling packages in the
OpenHearth workspace, checked out next to this repo: `elo_engine` (pairwise
ranking + merge), `openhearth_design` (the shared theme), `sanctuary_auth_core`
and `sanctuary_backup_ui` (the encrypted backup), and, for the tests,
`oh_fleet_conformance`. The paths are in `pubspec.yaml`. Drift code generation,
when needed:

```bash
dart run build_runner build --delete-conflicting-outputs --force-jit
```

## Privacy in one line

Ghost mode is the whole product: **zero network for app data, no accounts, no
analytics, no telemetry.** The household's data lives in a local SQLite database
on the device. Beside it are only the theme preference and the encrypted
backup's own state (recovery words, on-device snapshots). There is no network
client in the app. Android's own backup is the phone owner's choice, set in
Android settings; the encrypted backup is the private option. See
**[docs/privacy-model.md](docs/privacy-model.md)** — and you can check it
yourself.

## Documentation

Start at **[docs/README.md](docs/README.md)** (organized
[Diátaxis](https://diataxis.fr/)-style). The map:

- **[VISION.md](VISION.md)** — the one idea, the invariants, the honest scorecard.
- **[AGENTS.md](AGENTS.md)** — guide for agents and humans working in this repo.
- **[docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md)** — how it fits together.
- **[docs/concepts.md](docs/concepts.md)** — the domain model in prose.
- **[docs/spec/yellow-paper.md](docs/spec/yellow-paper.md)** — the reveal semantics, specified.

## License

MIT. Bundled content (the affinity deck) is CC0 / Public-Domain, verified
per-object — see [docs/cc0-image-sourcing.md](docs/cc0-image-sourcing.md).
