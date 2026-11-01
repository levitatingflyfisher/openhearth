# Reference: feature status

What's shipped, what's deferred, at a glance, as the code stands (the version
is in `pubspec.yaml`). The honest
narrative version is the [Vision scorecard](../VISION.md#honest-scorecard--built-vs-aspirational);
the caveats are in [limitations](../limitations.md).

## Shipped (real, tested)

| Area | Status |
|---|---|
| Three cadences (tick / count / timer) end-to-end | ✅ |
| FurrowRow Today grid + partial-bloom cells | ✅ (golden-tested, phone/tablet, textScale 1×–3×) |
| Inline logging: tap = today, long-press = fix past *tick* | ✅ |
| `LogTimeSheet` (chips +5/+15/+30, exact stepper, live stopwatch) | ✅ |
| Pure domain logic (value, progress, streak, best, clean-week) | ✅ (unit-tested) |
| Franklin 13-virtue seed (opt-in) + virtue-of-the-week | ✅ |
| Six awards (hardcoded checks, criteria written on Stats, never revoked) + gentle confetti | ✅ (`six_awards_test`) |
| Habit Detail (calm streak + heatmap), Stats (raw counts) | ✅ |
| Onboarding with starter templates | ✅ |
| Ghost mode (local-only, no account) | ✅ |
| Local storage (Drift/SQLite), schemaVersion 2 (soft-deleted habits) | ✅ |
| Android APK + installable web PWA, fully offline | ✅ |
| Bundled fonts (Lora + Nunito), no CDN fetch | ✅ (guarded by a test) |
| Concurrent-tap-safe mark writes | ✅ (regression-tested) |
| Encrypted backup/restore (`.ohbk`, seed phrase) | ✅ ([ADR-0008](../adr/0008-encrypted-backup-seed-phrase.md)) |
| Evening review (one pass down the day, reaching back a week) | ✅ (`review_screen_test`) |
| Choose the week's focus virtue; its row leads the grid | ✅ (`focus_virtue_test`) |
| Soft delete with Recently removed; Resting list for archived habits | ✅ (`soft_delete_test`) |
| Snapshot vault (Settings → Previous backups) | ✅ |
| Export as plain JSON (unencrypted) | ✅ |

## Deferred (schema- or key-ready, not wired)

| Area | Status |
|---|---|
| `weeklyCount` schedule + week-grained streak | ⏳ columns exist; UI treats as "any day" |
| Per-virtue precept editing | ⏳ key name reserved in a comment; nothing reads it, no editor |
| General award-criterion engine | ⏳ v1 hardcodes 6 checks |
| Inline past-edit for count / duration | ⏳ detail-screen only for now |

## Not built (aspirational)

| Area | Status |
|---|---|
| Sync / multi-device / Furrow-run cloud backup | ❌ by design (local-only — encrypted *manual* backup exists, see above; Android's own Google backup is the phone owner's option) |
| Multi-user / profiles | ❌ single-user by design |
| Token / Named auth tiers | ❌ stubs throw `UnimplementedError` |
| Reminders / nudges | ❌ by design ([ADR-0007](../adr/0007-no-dark-patterns.md)) |
| iOS / desktop builds | ❌ Flutter-capable, not built |
| Home-screen widget | ❌ Android registers a Sundial leftover that reads a `today_hours` value no Furrow code writes; it shows no habit data |

Legend: ✅ shipped · ⏳ deferred (groundwork present) · ❌ not built (often by
design).
