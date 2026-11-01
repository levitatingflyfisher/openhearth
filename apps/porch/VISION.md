# Vision

> The north star for Porch. If you (person or agent) are about to change something
> load-bearing, read this first — it says what must stay true and why.
> For *how it's built*, see [docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md);
> for *why each decision was made*, [docs/adr/](docs/adr/); for *what's actually built
> today*, the honest scorecard below and [docs/reference/feature-status.md](docs/reference/feature-status.md).

## The one idea

**Turn the porch light on.** The 19th-century front porch was a technology for ambient
availability: you sat outside, visible and approachable, and the people who already knew
you stopped by. Air conditioning and the television pulled everyone indoors, and the
"hey, you free?" text is a poor replacement — it makes you interrupt someone, wait, and
negotiate before a conversation can even start. The activation energy is high enough that
the call often just doesn't happen.

> **Porch is a presence signal, not a communication channel.** You turn your porch light *On*; the
> close friends already in your circle see the light is on; they reach you on whatever
> channel they already use — Signal, FaceTime, a phone call. Porch never carries the
> conversation. It only says the light is on.

The north star is not green dots viewed or widgets opened. It is **calls made**. If Porch
produces more real conversations between people who already love each other, it works. If
it becomes ambient social wallpaper — the *feeling* of connection without the substance —
it has failed on its own terms. That distinction informs every decision here.

## What this is

Two pieces, both deliberately minimal:

- **A Flutter app** (`app/`) — iOS + Android. A porch light *On / Off* control, a small feed
  of who in your groups is available right now, and a homescreen **widget** that is the
  primary surface: ambient, glanceable, no notification required. *(Today the screens
  are built and tested on the host, the widget is not built, and the app has never run
  on a phone. See the scorecard below.)*
- **A Go presence relay** (`relay/`) — a *blind relay*, not a backend-as-a-service. It
  has no accounts and no login (no email, no phone, no PII). A device reaches a group's
  channel, an invite or a mailbox by knowing its unguessable address, and the one signed
  request (ed25519) is a device draining its own mailbox
  ([ADR-0006](docs/adr/0006-capability-channels-no-session-plane.md)). It stores
  **end-to-end-encrypted** blobs only, keeps presence under a TTL so it expires on its
  own (in memory by default, in Redis when started with `-store=redis`), and keeps
  **zero access logs**. The relay is designed to see only ciphertext.

There is no chat, no calling infrastructure, no social graph to grow, no feed to scroll,
no location sharing, no accounts. Porch lubricates relationships that already exist; it
does not manufacture new ones.

## Design commitments (the invariants)

These are the load-bearing beliefs — the OpenHearth ethos, in Porch's voice. Breaking one
is a design regression, not a feature.

1. **Presence, never communication.** The app signals availability and nothing else. The
   moment it grows in-app messaging, calling, or a scrollable feed, it has become the
   thing it was built to avoid. ([ADR-0001](docs/adr/0001-presence-not-communication.md))
2. **Local-first, and the server is blind.** Display name and contact note live on the
   device. Anything that must travel does so as an **encrypted blob through a dumb relay** —
   never plaintext, never a BaaS. ([ADR-0002](docs/adr/0002-dumb-e2e-relay-not-baas.md))
3. **No account, ever, no PII.** Identity is a locally generated keypair. The relay
   stores no public key and sees one only when a device drains its own mailbox. It
   learns no email, no phone, no name.
   ([ADR-0003](docs/adr/0003-ed25519-identity-no-accounts.md))
4. **Ephemeral by design.** Presence is stored with a TTL and *structurally* cannot exist
   after it expires — it is not soft-deleted, it is gone.
   ([ADR-0005](docs/adr/0005-ttl-ephemeral-presence.md))
5. **No ads, no tracking, no data sales, no logs** — enforced by architecture, not by a
   promise. There is nothing to sell because nothing is collected.
6. **The widget is progressive enhancement, not a dependency.** The app works fully
   without background refresh, without push, without Google Play Services. Privacy-strict
   setups (e.g. de-Googled Android) are first-class, not an afterthought.
7. **Genuine craft.** Audited crypto only (libsodium) — we do not roll our own. High test
   coverage is the norm. Warm, not sterile — home-cooked software.

## Honest scorecard — built vs. aspirational

A guiding light has to tell the truth about where the light reaches. **Porch is
pre-release.** Every line of source and every comment in this repo was written by an AI
assistant; treat them as *an accurate record of what currently exists, offered with
gratitude and a grain of salt* — not as a specification and not as guaranteed-correct.
Verify a claim before you rely on it. **As of the ground-up v1 build** (a blind
from-the-PRD rebuild that replaced the scaffold — see
[ADR-0007](docs/adr/0007-ground-up-competition.md)) the line moved a long way, but it
has NOT reached "shipped":

**Real, tested, load-bearing (verified on-machine):**
- **The end-to-end encryption.** Real libsodium client crypto (`sodium`/`sodium_libs`,
  pinned): BIP39 identity, per-group symmetric keys with epoch rotation on membership
  change, sign-then-encrypt presence envelopes, deterministic roster fold + admin
  succession. In `app/lib/domain/`.
- **The presence relay.** The capability-channel blind relay (`relay/`) — all endpoints
  (invite, anonymous mailbox, stateless signed drain, TTL presence slots, bulletin) over
  a `Store` interface with an in-memory fake *and* real Redis 7; tested, vet-clean. Privacy is tested *structurally*: stored blobs are byte-identical to what
  was submitted (the relay provably never parses), and a zero-logging source-grep test runs with the relay's `go test` (CI that runs it
  exists since 2026-09-28 but has not run yet).
- **The app end to end.** Onboarding (silent keygen → 12-word reveal → default group),
  the porch light *On / Off* control (one control that shows its state) with expiry/tag, the friend feed with a *typed* staleness guard
  (`PresenceSnapshot` cannot be built without `fetchedAt`), groups (create/invite/join/
  leave/remove with rotation), an encrypted backup locked by 6 backup words — all wired through Riverpod against a
  relay-twinned fake **and** a compiled-relay integration harness. Suite totals are
  not recounted since 2026-07-10 (see HONEST-STATUS); `flutter analyze` clean.

**NOT yet real — the honest gaps (see [HONEST-STATUS.md](HONEST-STATUS.md)):**
- **It was built for Android once and has never *run* on a device.** One arm64 release
  APK was made (the `ground-up-preview` release), with `sodium_libs`
  bundling libsodium 1.0.20 into it. That APK could not have reached a relay: its
  manifest declared no `INTERNET` permission. The manifest is fixed since, and no APK
  has been built since, so no build carries the fix or any later work. Every platform
  seam — secure storage, the `sodium_libs` *runtime init*, `path_provider`, the widget
  bridge — has **zero** on-hardware coverage; the crypto is proven on host-VM libsodium
  only. *First sideload is first run.*
- **The homescreen widget is a spike, not a feature.** The iOS/Android widget UIs exist;
  nothing writes real presence into them and the long-press toggle isn't wired.
- **No background refresh, no push, no local-notification adapter** bound in production
  (the diff logic is real and tested; the notifier is a no-op).
- **The relay has never been deployed.** Everything network-real happened on localhost;
  the [Hetzner deploy walkthrough](docs/how-to/deploy-relay.md) is written, not executed.

Everything with *encrypted*, *presence*, and *feed* attached is now real and tested —
against fakes and a compiled relay, on a dev machine. Everything with *on a phone* or
*deployed* attached is still a hope. Keep that line bright — see
[docs/limitations.md](docs/limitations.md) before adopting or building on this.

## Horizons (problems, not a dated feature list)

The roadmap is framed as *problems* on purpose: pinning a pre-release app to dated
features invites the wrong kind of pressure. What endures is the open questions.

- **Near** — *Does it work on a phone?* The app has never run on one: the libsodium
  runtime, the keystore, the share sheet and the release build are all unverified on
  hardware. And *where is the relay?* None is deployed, so today every light stays on the
  phone that turned it on.
- **Mid** — *Who is told, and when?* Joining is a two-sided handshake that neither side
  hears about until they open the app; there is no background refresh, no notification
  adapter and no widget bridge, and the app must stay complete without push. *How few
  steps can the light take?* The sheet between the tap and the light is still contested.
- **Far** — The residual risks Porch chooses to accept rather than pretend away:
  **traffic analysis** (a relay can see *that* two devices share a channel, even if it
  cannot read *what*) and the **drain key** (draining a mailbox names a public key to the
  relay). The honest response is to name them, bound them, and never claim they don't
  exist. Group changes today rotate one shared key; a larger or busier group may need a
  real group-key protocol.

## The name

**Porch.** You are not scheduling and you are not broadcasting. You are sitting on the
porch with the light on. Your friends already know your door — Porch just tells them the
light is on right now. The open door for your friend group.
