# ADR-0001 — Presence signal, not a communication channel

**Status:** Accepted

## Context

The problem Porch addresses — the friction of reaching a close friend on a whim — could be
"solved" by building a nicer messenger or calling app. That path is a trap. The friction
isn't the absence of another chat app; people already have Signal, FaceTime, WhatsApp, and
the phone. The friction is the *activation energy* of interrupting someone cold and
negotiating whether now is a good time. A communication app doesn't remove that; it adds one
more inbox.

The moment an app carries the conversation, it acquires a feed, notifications that demand
attention, presence-as-performance, and eventually the whole attention-economy shape Porch
exists to avoid.

## Decision

Porch signals **availability and nothing else.** You tap *Available*; your circle sees the
light is on; they reach you on whatever channel they already use. Porch's responsibility
ends when it has shown the light is on. Explicitly out, by design: in-app chat, calling
infrastructure, a social graph/feed, scheduling, contact management as a system, location
sharing, and read receipts.

## Consequences

- **Positive:** the product stays tiny and legible. No message store, no call servers, no
  moderation surface. The privacy story is dramatically smaller because Porch never touches
  content. The metaphor (a porch light) stays a usable design test — off-metaphor features
  are easy to reject.
- **Positive:** it leans on channels people already trust rather than asking them to move
  their relationships onto a new platform.
- **Negative / tension:** users will ask for "just a quick reply" or "just tap to call."
  Each is a step back toward being a messenger. The contact preference is deliberately a
  single text field, not a deep-link system, to hold this line (see [concepts](../concepts.md)).
- **Guardrail:** the success metric is **calls made** (proxied by same-day re-availability),
  *not* engagement. If glances rise while calls stay flat, Porch has become ambient
  wallpaper — a failure by its own definition, and a signal to cut, not add.
