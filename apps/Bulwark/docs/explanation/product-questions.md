# Open product questions

*Understanding-oriented. These are choices a product requirements draft left open.
The app is the spec for everything already built; this page lists what it does not
settle. Figures are targets from a draft, not measured results.*

## Product or tool: already answered

[VISION](../../VISION.md) states that Bulwark is local-only, with no account, no telemetry
and no subscription, and that the business-model half of the source draft is void for
this app. The draft's paid tier (a free cap of 10 habits, premium features, family
sharing) is therefore history. The questions below are the ones that survive that ruling.

## A caffeine-free toggle

The draft added a switch that hides caffeine cutoffs, skips the caffeine step in the
adoption sequence, and flags products that contain tea or other excluded ingredients.
Nothing in the repo does this yet. Open: should it be a setting or a preset, and can the
shopping list carry ingredient flags at all, given that shipped content names no products
([ADR-0004](../adr/0004-de-personalization-law.md))?

## Mode presets

The draft described optional one-tap bundles that skip the one-to-three queue because the
person is in a particular situation. The repo has one, `newParent`. Open: which other
situations earn a preset, and whether the breastfeeding variant is a second preset or a
toggle inside the first. Any variant needs clinician review before it ships (see the
[ideas list](ideas.md)).

## Targets for success

The draft's targets, for judging a first release:

- 50 percent of people who finish onboarding still check in weekly at 30 days.
- At least 5 habits graduated at 90 days, on average.
- A daily check-in under 45 seconds on average.
- A net promoter score of 40 or more.

The app collects no analytics ([privacy model](../privacy-model.md)), so none of these
can be measured. Open: keep them as design aims for the wall and check-in, or drop them.

## Features the draft put in a later version

Health-data links, a correlation view, an optional question-answering layer, bloodwork
tracking, seasonal adjustments, family sharing and adaptive sequencing. VISION rules out
the correlation view; the others either need a network or are not yet decided, so each
needs its own decision before design work.
