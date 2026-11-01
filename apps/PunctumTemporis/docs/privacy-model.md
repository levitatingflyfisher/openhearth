# Privacy model

Punctum Temporis holds an unusually sensitive dataset — years of a family's
faces, homes, and daily locations. This page states exactly what does and does not
leave the device, and how you can check it yourself. See
[ADR-0001](adr/0001-local-first-no-accounts.md) and
[ADR-0004](adr/0004-on-device-face-crop.md) for the decisions behind it.

## Threat model (who this protects against)

- **The app maker / a cloud service** — there is no service; there is nothing to
  hand over, subpoena, breach, or monetize. Not applicable by construction.
- **Passive network observers / trackers** — the runtime makes no requests
  carrying user data, so there is no traffic to observe.
- **Other apps on the device** — clips, thumbnails, faces, and metadata live in
  the app-private directory (OS-sandboxed); only *compiled* montages are written
  to the public `Movies/` folder, and only because a finished film is meant to be
  shared.
- **A malicious backup you were given** — restore treats the ZIP as untrusted
  input (zip-bomb, ZIP-Slip, path-poisoning defenses — see
  [ADR-0005](adr/0005-untrusted-backup-hardening.md)).

Explicitly **out of scope** (see [limitations.md](limitations.md)): a thief with
your *unlocked* phone, forensic recovery of the raw files, and anyone you
*choose* to share a clip or backup with. There is no at-rest encryption beyond the
OS sandbox yet.

## What leaves the device

| Data | Leaves at runtime? | Notes |
|---|---|---|
| Clips, thumbnails, face images | **No** | app-private storage / OPFS |
| Clip metadata (dates, tags, GPS, people) | **No** | `metadata.json` and its snapshots, on device |
| Face embeddings & recognition | **No** | ML Kit + MobileFaceNet run on device |
| GPS → city label | **No** | offline geocoder over a bundled dataset |
| Fonts | **No** | bundled in `assets/fonts/`, not fetched from Google |
| Crash/usage analytics | **No** | there is no analytics SDK |
| A clip or montage you tap "share" on | **Yes — you initiated it** | goes wherever you send it, via the OS share sheet |
| A backup you export | **Yes — you initiated it** | a ZIP locked with your 12 recovery words, saved to a folder you pick or sent through the OS share sheet (a browser download on web); without the words it cannot be opened |

The only egress is a **deliberate user action**. Nothing is automatic, scheduled,
or background.

## Privacy-preserving details worth knowing

- **Faces are stored cropped.** A person's reference image is cropped to the
  detected face box, not the surrounding room — so backups and the face gallery
  don't incidentally hoard everything behind every face
  ([ADR-0004](adr/0004-on-device-face-crop.md)).
- **Location is coarse and local.** The label is a nearest *city*, computed on
  device — never a street address, never a lookup service.
- **Face recognition is opt-in by omission.** With no model file present, the
  entire face system is inert.
- **A backup is locked with your recovery words.** Each file is sealed with
  ChaCha20-Poly1305 under a key from the words (the shared OpenHearth core),
  so a shared or lost backup file shows nothing without them. The words are
  the one thing to guard, on paper; lose them and the backup is lost too.
- **Android's own backup may also copy app data to Google.** The manifest
  leaves `allowBackup` at its default (on), so if the phone's owner turns on
  Google backup in Android settings, Android may copy this app's data. Android
  skips an app whose data is large (25 MB), so a video journal is often left
  out. The app's own ZIP is the copy that holds the clips, and the backup
  screen says so.

## Verify it yourself

You don't have to trust this page:

1. **Read the deps.** `pubspec.yaml` has no analytics/crash/BaaS packages
   (no Firebase, Sentry, Amplitude, etc.). Network-capable packages present are
   there for GPS, media, and sharing — not for exfiltration.
2. **Grep for a network client.** Search `lib/` for `http`, `dio`, `HttpClient`,
   `Socket`, `fetch` — you'll find no code uploading clips, thumbnails, faces, or
   metadata.
3. **Watch the traffic.** Put the phone behind a proxy (or use airplane mode) and
   exercise capture → recognize → compile. Everything works offline; no user data
   is sent.
4. **The font test proves one case.** `test/theme/offline_fonts_test.dart` locks
   every visual style to bundled font families, so a regression to runtime font
   egress fails the build.
