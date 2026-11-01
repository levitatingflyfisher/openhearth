# Concepts

The ideas that make Porch what it is. This is the *why it's shaped this way* doc; for what
exists in code, see [feature-status](reference/feature-status.md).

## The porch light

The metaphor is load-bearing, not decorative. A front porch with the light on is:

- **Ambient** — you don't have to ask; the state is just *visible* to people walking by.
- **Low-obligation** — the light being on is an invitation, not a summons. No one owes you
  a visit, and you owe no one an explanation for turning it off.
- **Local** — it's for the people who already know your door, not for strangers.
- **Ephemeral** — it's on *now*. It says nothing about tomorrow, and no one keeps a log of
  when it was on.

Every product decision is checked against the metaphor. A feature that turns the light into
an obligation (read receipts), a schedule (soft commitments), or a billboard for strangers
(discovery) is off-metaphor and gets cut.

## Presence, not communication

The single most important line in Porch: **it signals availability and never carries the
conversation.**

You turn your porch light *On*. Your friends see the light is on. Then they call you — on Signal,
FaceTime, WhatsApp, the phone — *the way they already call you*. Porch's job ends the
moment it has told them the light is on.

This is why Porch is **not** a chat app, a calling app, a social network, a scheduler, a
contact manager, or a location-sharing app. Each of those would have Porch carrying or
mediating the interaction, which is exactly the friction it exists to remove. Alice already
knows how to reach Bob; he's her friend. Porch answers "is anyone I already love available
right now?" — not "who might want to know me?" See
[ADR-0001](adr/0001-presence-not-communication.md).

## Availability, with a TTL

Turning the light on is one tap. It carries:

- An **expiry** (default 1 hour; 30 min / 1 h / 2 h / 4 h, or a custom number of
  minutes, capped at 4 hours). The light turns itself off — no "remember to log out"
  chore, and no stale "available" state misleading your friends. *Off* ends it early.
- An optional short **context tag** (one of the presets *walking*, *chores*, *driving*, *at my desk*, *reading*, or up to 24
  characters of your own) — a hint about *what kind* of company you're up for.
- A **group scope** — you choose which group(s) the light is on for.

The TTL isn't just UX; it's a privacy property. The relay keeps a presence slot only for
its TTL (in memory or in Redis) and it is **structurally gone** when it expires — see
[ADR-0005](adr/0005-ttl-ephemeral-presence.md).

## Groups

- On first launch you get one group, **"My Porch."** Most people will only ever need it.
- You can create more named groups to compartmentalize (family vs. college friends vs.
  work). You can be in several.
- You **invite** by a private, one-time link that expires in 72 hours and can be
  regenerated. There is no public discovery — you cannot find a group by searching.
- **Leaving is silent.** No "Bob left" notice — that would trap people in zombie groups out
  of social friction.
- Admin is the group's creator, transferable; if an admin leaves without transferring, the
  oldest remaining member becomes admin by a deterministic client-side rule — no server
  involvement.

## Contact, as a text field (not a system)

Each user has a single optional, freeform **preferred-contact** note — "Signal: @bob",
"just call me", "WhatsApp +1-555-…" — set once, visible to their Porch contacts. That's the
whole thing: no per-group grants, no handle repository, no deep-link platform matrix. Alice
usually already knows how to call Bob; the note exists for the edge case where she genuinely
doesn't. Keeping it a text field instead of a system is a deliberate simplification (an
earlier, much larger contact-handle design was cut for exactly this reason).

## Identity without accounts

There is no sign-up. On first launch the device generates its identity from 16 random
bytes, shown to you as **12 recovery words**; the keys derived from them never leave the
device. No email, no phone, no PII. The relay has no accounts: it sees a public key only
when a device drains its own mailbox. See
[ADR-0003](adr/0003-ed25519-identity-no-accounts.md),
[ADR-0006](adr/0006-capability-channels-no-session-plane.md) and the
[security model](security-model.md).

The trade-off is **recovery**: with no account, losing your device, your words and your
backup means losing your identity. The 12 words bring back the identity alone; a
**backup file locked by 6 backup words** (ciphertext; the relay never sees it) brings back the identity
and the groups it held. Restoring happens on a new phone's first screen. Passkeys are not
used: the recovery decision is seed-first
([ADR-0004](adr/0004-seed-backup-recovery-over-passkeys.md),
[PASSKEY_SPIKE.md](PASSKEY_SPIKE.md)).

## The blind relay

The server is a **dumb relay**, not a backend-as-a-service. Access is by knowing an
unguessable channel, invite or mailbox address, not by logging in; it stores and returns
only end-to-end-encrypted blobs, keeps presence for its TTL, and writes **zero logs**
([server-api](reference/server-api.md)). It is deliberately *not* Firebase/Supabase/Auth0 —
a BaaS would put a third party between friends and hand it the metadata Porch exists to
protect. See [ADR-0002](adr/0002-dumb-e2e-relay-not-baas.md).

## The widget as the primary surface

*Not built yet (a spike only).* The homescreen **widget** — a count of available friends,
or a couple of names with tags — is the intended main way you experience Porch: ambient and glanceable, no app-open required,
no notification demanded. Notifications are off by default and exist only as a power-user
escape hatch. Crucially, the widget is **progressive enhancement**: the app is designed to
work fully without it, and the widget shows last-known state with a timestamp when
background refresh is off — never blank, never silently stale.

## The success metric that keeps Porch honest

Porch measures itself by **calls made**, proxied by same-day re-availability. If widget
glances climb while re-availability stays flat, Porch has become ambient social wallpaper —
the feeling of connection without the substance — and by its own definition that is
failure, not success.
