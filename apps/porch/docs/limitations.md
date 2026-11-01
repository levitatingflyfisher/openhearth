# Limitations

Read this before adopting Porch or building on it. Two kinds of limitations live here:
things Porch **deliberately does not do** (by design, and won't), and things that are
**not built yet** (because Porch is pre-release).

## Deliberate non-goals (by design — not coming)

Porch is a presence signal. These are cut on purpose; each would turn the light into
something it shouldn't be. See [concepts](concepts.md) and
[ADR-0001](adr/0001-presence-not-communication.md).

- **No in-app chat or calling.** Porch tells your friends the light is on; they reach you on
  a channel they already use. It never carries the conversation.
- **No social network, no feed, no discovery.** You can't find people or groups by
  searching. Porch lubricates relationships that already exist; it doesn't manufacture new
  ones.
- **No read receipts, ever.** Seeing who viewed your status turns presence into a
  performance and manufactures social anxiety. This is a product value, not a missing
  feature.
- **No leave notifications.** Leaving a group is silent, so no one is trapped in a zombie
  group by social friction. (Joining is a passive positive signal.)
- **No scheduled availability.** "Usually free weekday mornings" is a soft obligation and
  goes stale; a stale schedule is worse than none. Porch is *the light is on right now*.
- **No location sharing / meetup mode.** "I'm available for a call" and "I'm at this coffee
  shop" are different trust models. Location is a separate, higher-stakes product, not a tag
  bolted onto availability.
- **No ads, no tracking, no data sales, no accounts, no PII.** Architecturally there is
  nothing to sell.

## Not built yet (pre-release)

The relay, the end-to-end encryption and the app's screens are built and tested on a
development machine. What is **not** real yet — do not rely on it:

- **It has never run on a phone.** No emulator or device run exists; every platform seam
  (secure storage, libsodium loading on device, the share sheet, file locations) is
  untested there.
- **No relay is deployed.** The app ships a placeholder relay address that can never
  resolve, and until you enter a relay you run (Settings → Relay server) everything stays on
  one phone. Home says so.
- **The homescreen widget** is a spike: the iOS and Android widget files exist, but nothing
  writes presence into them.
- **No background refresh, no push, no local notification adapter.** The app polls every
  25 s while open.
- **No `porch://` deep links.** Invites are pasted as codes.

The per-component line is in [feature status](reference/feature-status.md); the full
ledger is [HONEST-STATUS.md](../HONEST-STATUS.md).

## Scoped out of v1 (planned to remain possible)

Deferred, but the architecture is meant not to foreclose them:

- **Multi-device.** One keypair, one primary device for now. Simultaneous phone + tablet
  needs a Signal-style linked-device key exchange; the key model should leave room for a
  per-user device list rather than assuming one key per identity.
- **Rich per-platform calling.** Deep links (`signal://`, `facetime://`, `tel:`, …) are a
  polish layer on top of the contact text field, added incrementally without touching the
  crypto — not a v1 concern.

## Accepted residual risks

Porch does not defend against everything — and says so:

- **Traffic analysis.** A blind relay still sees connection timing and volume; it can infer
  *that* a group is active, not *what* is said. Accepted.
- **Silent-push metadata (future).** Push and background widget updates are not built. If
  they are, they would leak *that* a push was delivered to FCM/APNs (never its content);
  the design keeps them optional.
- **Endpoint compromise.** Porch can't protect data on a device an attacker already
  controls.

Details and the full threat model: [security-model.md](security-model.md).

## Known gotchas

- **The backup file starts inside the app.** It is written to the app's own storage, which
  on Android is deleted when the app is uninstalled. Use *Share / save backup file* after
  making a backup to keep a copy somewhere that lasts.
