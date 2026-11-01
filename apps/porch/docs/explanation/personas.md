# Personas

Agents drive the real porch build as these people, per the fleet testing
rule. porch is **pre-release**: the app has never run on a phone, the widget
is not built, notifications are a no-op, and no public relay exists. Run a
local `relayd` (in-memory) and point Settings at it, or use the web preview,
and record anything that only fails on a device as untested. Each scenario
gives a start state, plain steps, what success looks like, and what to check.
"Standard checks" means: text scale 1.3 at 360 dp width, dark mode, the relay
stopped (offline), and every error in plain words with a next move.
Scenarios aim at the weak spots found by the September 2026 lens audit.

## Primary: Ifeoma, a new parent who misses their friends

Ifeoma is 34, home with a four-month-old, and their three closest friends
never know when a call would be welcome. They want to tap once when the baby
naps and let the group ring them on Signal.

- **Goal:** turn the porch light on in one tap and know the group saw it.
- **Context:** one-handed, baby asleep on the other arm, often in a dim room.
- **Would quit if:** the light looks on but nobody could see it.

**I1. Relay honesty.** Start: fresh install, Settings still on the shipped
placeholder relay. Steps: finish onboarding; turn the porch light On; read Home.
Success: Home says the relay is unreachable or unset, not "You're on the
porch" as if delivered. Check: stop the local relay mid-session and confirm
Home says so; standard checks.

**I2. One tap.** Start: one group, a working local relay, defaults set in
Settings. Steps: turn the porch light On. Success: the light turns on from
remembered defaults, or the sheet's extra step is recorded as a finding;
Home repaints at once, not after a 15-second wait. Check: with zero groups,
the button is disabled or explains why.

**I3. Settings kept.** Start: Settings. Steps: type a contact note
("Signal: @ifeoma"); press Back without tapping Save; reopen Settings.
Success: the note is kept. Check: dark mode.

## Secondary: Marcus, a friend who wants to call back

Marcus is 36, Ifeoma's oldest friend, a shift worker with a teenage son.

- **Goal:** see who is available, reach them in one step, and keep their
  identity when they change phones.
- **Context:** glancing between shifts, text scale 1.3.
- **Would quit if:** they must memorise a handle and switch apps by hand.

**M1. Joining a group.** Start: second install, an invite code from
Ifeoma's device. Steps: enter the code on Join; tap Check now while Ifeoma
has not opened the app. Success: the waiting screen says what is happening
and for how long; Ifeoma's device tells them someone is waiting. Check: a
wrong code gives a plain sentence with the next move.

**M2. Reaching Ifeoma.** Start: Ifeoma's light is on with a contact note.
Steps: tap Ifeoma in the feed. Success: the note is visible in the row and
opens or copies the handle in one tap; no dialog with only Close. Check:
avatars keep initials when a tag emoji is set; emoji tags have words.

**M3. New phone.** Start: fresh install, a backup file and its 6 backup words
from Marcus's old device. Steps: go through onboarding looking for restore;
type the words with a typo; then in Settings make a new backup. Success:
restore from file works, or its absence is recorded; a filled button never
quietly makes a new identity; the wrong words get an inline message, not a
silent close. Check: onboarding never shows raw exception text.
