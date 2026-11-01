# Reference: feature status

What is shipped, partial, or not built — as of the **current tree** (past the 1.0.0 release; see Unreleased in
[CHANGELOG.md](../../CHANGELOG.md)). Cross-check against
[VISION.md § Honest scorecard](../VISION.md#honest-scorecard--built-vs-aspirational)
and [limitations.md](../limitations.md). Remember the [grain-of-salt](../../AGENTS.md#take-the-code-as-current-state-not-gospel):
this reflects the code as read, verified by the test suite where noted.

| Area | Status | Notes |
|---|---|---|
| **Feeding tracker** | ✅ Shipped | breast/bottle/solid, side, ml & oz, live timer; tested |
| **Sleep tracker** | ✅ Shipped | nap/night, start-stop timer, location; tested |
| **Diaper tracker** | ✅ Shipped | wet/dirty/both/dry, colour; tested |
| **Growth + WHO curves** | ✅ Shipped | weight/height/head vs boys/girls percentiles; tested |
| **Medicine log** | ✅ Shipped | name, dose, unit, time; tested |
| **Vaccine history** | ✅ Shipped | name, dose #, scheduled/administered, provider; tested |
| **Dashboard** | ✅ Shipped | quick-log buttons, active-timer card, daily summary strip |
| **Calendar** | ✅ Shipped | monthly view with per-day event markers |
| **Timeline** | ✅ Shipped | reverse-chronological feed with filter chips |
| **Statistics** | ✅ Shipped | feeding-trend, sleep-pattern, diaper-frequency charts; 7/14/30-day windows |
| **Doctor summary** | ✅ Shipped | at-a-glance summary for appointments |
| **PDF export** | ✅ Shipped | doctor summary as PDF via share sheet |
| **CSV export** | ✅ Shipped | summary & raw CSV, **formula-injection-safe** (tested) |
| **Multiple babies** | ✅ Shipped | profiles + switcher; one active at a time |
| **Home-screen widget** | ✅ Shipped | baby name + last feed/sleep/diaper + active timer |
| **Dark mode / Material 3** | ✅ Shipped | follow phone (default), Light or Dark from the top bar, remembered across launches; dynamic colour on Android 12+ |
| **Encrypted backup / restore** | ✅ Shipped | app-side flow + OHBK format real & tested, real audited crypto (`sanctuary_auth_core`, sibling path dep); pre-rewire (CI-stub-era) exports are a known, documented incompatibility — see [limitations.md](../limitations.md#known-incompatibility-pre-rewire-stub-era-backups) |
| **Seed-phrase recovery** | ✅ Shipped | generate/confirm/derive-key flow on the real `sanctuary_auth_core` module |
| **Two-phone sync** | ⚠️ Shipped, early | opt-in, through a household relay and/or phone to phone on the same Wi-Fi (show or type a code, QR link; Android, not the PWA); field-level merges, lasting Undo, Forget this phone; status says which path last synced; two-phone tests through the real relay binary and over loopback Wi-Fi (`test/sync/`). No mDNS discovery or photo sync; restore is refused while sync is on |
| **Note for the next shift** | ✅ Shipped | append-only handoff notes on Home; sync to the other phone; kept in backups |
| **"Named"/account tier** | ❌ Not shipped | `AuthTier.named` exists in the enum; only `ghost` runs |
| **Reminders / notifications** | ❌ Not built | no scheduled reminders |
| **App-store release** | ❌ Not done | `applicationId` is `com.openhearth.lullaby`; the release build signs with the debug key; no release workflow |
| **Screenshots** | ❌ Pending | README says "coming soon" |

## Platforms

| Target | Buildable | CI-verified |
|---|---|---|
| Android | ✅ | analyze + test on Linux (no APK build, not device) |
| iOS | ✅ | ❌ |
| Linux desktop | ✅ | ❌ |
| Web | ✅ (WasmDatabase) | release build compiles (not opened in a browser) |

CI (`.github/workflows/ci.yml`) runs `flutter analyze`, a web release build and
`flutter test` on one Linux runner for every push to `master` and every PR. No
other platform build is exercised by CI.
