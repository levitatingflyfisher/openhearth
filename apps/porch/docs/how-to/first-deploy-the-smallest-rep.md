# Your first deploy — the smallest reversible rep

This is not the production guide (that's [deploy-relay.md](deploy-relay.md)). This
is the *first* one: the smallest, most reversible version of "I ran a server,"
designed so your nervous system learns that the sky holds.

You built a relay that is **safe when it fails.** It stores only ciphertext
keyed by capabilities it can't compute; breach it completely and the attacker
gets opaque blobs that expire on their own. You do not have to be trusted for
this server to be safe — that was the whole point, and it means the scary part
of "running a server" (holding something that could hurt people if you get it
wrong) mostly isn't here. So the only thing left to practice is the *motion*.

## The rep

Deploy the relay to a **managed host** (no VM to babysit, no 3am sysadmin),
point **one** test build of the app at it, use it for **a week**, then **delete
it.** Nothing real is at stake: no friends, no data that matters, and a delete
button you can press at any moment.

The goal is not to launch Porch. The goal is to have started a server and
stopped one, and noticed that nothing bad happened.

### 1. Pick a host you can delete in one click

[Fly.io](https://fly.io) or [Render](https://render.com) both run a container
with a real "Destroy" button. The relay is a single scratch image
(`relay/Dockerfile`). For this rep it needs nothing else: with no flags,
`relayd` keeps everything in memory, which is exactly right for a week of
presence that expires on its own anyway (a restart just empties it).

```bash
# Fly, from repo root:
cd relay
fly launch --no-deploy                 # generates fly.toml; accept defaults
fly deploy
fly status                             # note the https URL it gives you
```

`relayd` reads no environment variables. Redis is for the production guide,
and it is chosen with flags (`-store=redis -redis-url redis://host:port`),
listed in [deploy-relay.md](deploy-relay.md).

You now have `https://something.fly.dev`. That's your relay. It has your name on
a bill somewhere — that's the part that feels big, and it's also ~$0 at this
scale and gone the moment you destroy the app.

### 2. Point one app build at it

```bash
cd ../app
flutter run --dart-define=PORCH_RELAY_URL=https://something.fly.dev
```

Onboard, create your porch, turn the porch light **On**. Generate an invite, open it on a
second device or a second run, and watch one light turn on from the other.
That's the product working against a server you deployed.

### 3. Live with it for a week

Leave it running. Tap Available a few times. Notice: the bill doesn't spiral,
nobody emails you, the server doesn't catch fire while you sleep. This is the
actual content of the rep — the *uneventfulness* is the lesson.

### 4. Delete it

```bash
fly apps destroy something-porch       # or the Destroy button in the dashboard
```

Gone. You started a server and ended one. The thing you were frozen on is now a
thing you have done and undone. That's the whole exercise.

## What this is deliberately NOT

- **Not** the real deploy. When you're ready for friends, [deploy-relay.md](deploy-relay.md)
  has the Hetzner-Finland path from the PRD (outside Five Eyes, ~$5/mo, your own
  VM), Caddy with logging off, and the production checklist.
- **Not** a commitment. A destroyed Fly app leaves nothing behind — no LLC, no
  Stripe, no domain, no users. The next step after this rep is *another* small
  rep, not a launch.

## Honest preconditions (so the rep doesn't fail for a boring reason)

The relay is real and tested; the *app* has never run on a phone (see
[HONEST-STATUS.md](../../HONEST-STATUS.md)). So the likeliest snag in this rep is
a device-glue bug (secure storage, the `sodium_libs` native binary, the widget
bridge) — not the server. If the app misbehaves on first run, that's expected
and it's a client-side fix, not a sign the deploy went wrong. The server half —
the part you're practicing — is the solid half.
