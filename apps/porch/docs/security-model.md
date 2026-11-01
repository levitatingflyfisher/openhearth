# Security & Privacy Model

A presence tool asks people to trust it with something intimate: *who I would take a call
from, and when I am around*. That trust has to rest on architecture you can check, not on
a promise. This page states the threat model, what is protected and how, and what is
**not** protected or **not yet built**. It describes the current tree (`app/` and
`relay/`) and the capability-channel design of [ADR-0006](adr/0006-capability-channels-no-session-plane.md).

> [!IMPORTANT]
> **Porch is pre-release.** The client crypto and the relay are built and tested on the
> host (Dart VM against the real libsodium; Go tests; one test compiles the real relay and
> drives two real clients through it). The app has **never run on a device**, and **no
> relay is deployed**. The authoritative built-versus-not split is
> [HONEST-STATUS.md](../HONEST-STATUS.md). Tags below: **[built]** = code plus a test that
> fails if it stops being true; **[not built]** = designed or promised only.

## Threat model

**The adversary:** someone with **full control of the relay**: its memory or Redis, and
all traffic arriving at it.

**The claim:** at full relay compromise the attacker gets anonymous key hashes and opaque,
TTL-expiring ciphertext filed under random-looking capability ids, with no stored link
between them: no names, no contact notes, no group names, no rosters, no social graph.

**Not defended against:** a compromised phone (whoever holds your unlocked phone is you),
and traffic analysis (the relay sees *that* an IP polled *which* capability ids, and
when). See [Residual risks](#residual-risks-accepted-not-hidden).

## Identity: a keypair, no account **[built]**

- Onboarding generates 128 bits of entropy on the phone and shows it as 12 BIP39 words.
  The signing (ed25519) and box (X25519) keypairs are derived from it with libsodium's
  KDF (`app/lib/domain/identity.dart`). No email, no phone number, no server call.
- The entropy lives in the platform keystore (Android Keystore / iOS Keychain) through
  `flutter_secure_storage`. It stays on the device: Android's backup rules exclude it,
  and on iOS and macOS the keychain items are `first_unlock_this_device`, so they never
  ride in iCloud or computer backups (`secure_storage_options_test.dart` pins the
  options; not checked on a device). **On the web preview it lives in the browser's
  localStorage**, a real downgrade the app states on screen (`web_preview.dart`).
- The 12 words have no reset path, by design: no server holds a copy.

## The relay is blind: capability channels **[built]**

Per [ADR-0006](adr/0006-capability-channels-no-session-plane.md) there is **no session
plane**: no login, no tokens, no stored public key per user.

- Each group has a 256-bit symmetric key with an epoch counter. Its wire address
  (`channelId`) and each member's presence slot are derived from that key
  (`app/lib/domain/keyring.dart`), so the relay files blobs under ids it cannot link to
  anyone.
- **Channel plane** (`/v1/ch/{id}/presence`, `/v1/ch/{id}/bulletin`): authorized only by
  knowing the id. The client sends no identity material on these paths; a structural test
  fails if it does (`app/test/data/api_client_test.dart`), and the relay reads none
  (`TestChannelPlaneReadsNoIdentity`).
- **Mailbox plane** (`/v1/mailbox/{id}`): posting is anonymous (rate-limited,
  size-capped). Draining is a stateless ed25519-signed request with ±300 s freshness and
  a replay cache (`relay/internal/api/sigauth.go`).
- **Invites** (`/v1/invites/*`): a single-use token in the link; the relay holds only an
  escrowed, encrypted blob and deletes the grant after it is fetched.

## What leaves the phone

| Data | What the relay holds | Status |
|---|---|---|
| Presence ("light on", tag, expiry) | an encrypted blob in a slot with a TTL (at most about 4 h) | **[built]** |
| Display name, contact note | nothing in plaintext: they travel inside encrypted, signed roster operations | **[built]** |
| Group name, roster, keys | nothing in plaintext: rosters are signed operations inside envelopes; new keys go to each member's mailbox, sealed to their box key | **[built]** |
| Invite | an encrypted escrow blob under a random id, 72 h at most | **[built]** |
| Notification choices, on-device stats | nothing: computed and kept on the phone | **[built]** |
| Your IP address | seen per request, used only for in-memory rate limiting, never stored or logged | **[built]** (`router.go` `clientIP`) |

Every channel payload is one envelope (`app/lib/domain/envelope.dart`): canonical JSON,
signed with the sender's ed25519 key, then sealed with XChaCha20-Poly1305 under the
group key, with `porch/v1 ‖ channelId ‖ epoch` as associated data. A blob that fails to
open or verify is dropped silently: a compromised relay can inject garbage but cannot
forge a friend. The relay stores exactly the bytes it was sent
(`TestStoredBlobsByteIdenticalEndToEnd`). The same inventory is in the app, under
Settings → What leaves your device.

## Membership changes rotate the key **[built]**

Removing a member rotates the group key at once (`app/lib/domain/rotation.dart`,
`app/lib/data/group_repo.dart`): a new key and epoch, a new channel address, the new key
sealed to each remaining member's mailbox, each delivery sent after an independent random
delay of up to 30 s so the fan-out is not one burst. The removed person's old key neither
decrypts nor addresses the new channel, and every outstanding invite is voided so its
escrow cannot hand them the new key. Leaving is silent: no one is notified. Because the
removal takes effect the moment it runs, the app asks before removing rather than
offering an Undo.

## Backup **[built]**

A backup file holds the identity entropy and the whole encrypted state (group keys,
rosters, contact notes), sealed with XChaCha20-Poly1305 under a key derived by
libsodium's password hash at its MODERATE limits (`app/lib/domain/identity.dart`). The
password is 6 backup words (66 bits) that Porch derives from the identity and shows
beside the 12 recovery words; the person never picks it. Restore refuses anything but 6
list words, and refuses a file whose header asks for more work or memory than
libsodium's SENSITIVE limits, before any key is derived.

The file stays out of automatic backups. It is written to a `backups` folder under the
app support folder, which the system never clears to free space. On Android that is
`files/backups`, which the backup rules exclude. On iOS and macOS the folder is marked
excluded from backup (`NSURLIsExcludedFromBackupKey`) before each file is written, and
no file is written if that fails (`app/lib/backup_folder_adapter.dart`; the Dart side is
tested on the host, the few lines of Swift have not run). It leaves the phone only when
the person shares it.

What the 6 words open, plainly:

- **The 6 backup words together with any backup file give the whole identity and every
  group.** Any file, old or new: the words are the same for every file this identity
  makes. This is the price of a backup that restores everything, and HONEST-STATUS
  names it.
- **The 6 backup words cannot be changed.** Porch derives them from the identity, so
  they last as long as it does. If they leak, the answer is a new identity: Settings,
  "Start over with a new identity". Porch leaves every group first, while the old
  identity still exists, and the other members' phones change each group's key when
  they see the leave. Any invite still open is voided and its link burned. Only then
  does the phone delete its backup files, its state and its keys, and open onboarding
  for new 12 words; the person joins the groups again by invite. If a group can't be
  reached, Porch names it and deletes nothing unless the person chooses to go on.
  Backup files already shared or saved elsewhere stay where they are, and hold an
  identity that is no longer in any group. **Until another member's app has seen you
  leave** and changed that group's key, a leaked old copy still holds the current key
  and can read that group's traffic (its own posts are dropped). A group whose other
  members are all offline stays readable to such a copy until one of them comes back
  online and sees the leave.
- **The 6 backup words alone, without a file, give nothing.** They come from a
  separately labelled hash of the identity, so they reveal nothing usable about the 12
  words, and the relay holds no backup file.

The screen that shows the 6 words says the same in one short note.

## Relay posture

- **No logs [built].** The serving packages contain no logging calls
  (`TestNoLoggingInServingPackages`), net/http's error log goes to `io.Discard`, and the
  compiled-relay integration test asserts zero bytes of output across a full session. The
  systemd unit in `relay/ops/` sends both streams to null.
- **Ephemeral by TTL [built].** Presence, invites, grants and replay entries expire by
  store TTL (memory or Redis 7), not by soft delete. See
  [ADR-0005](adr/0005-ttl-ephemeral-presence.md).
- **Self-hostable [built, never deployed].** One stdlib Go binary plus an optional Redis.
  `relay/ops/DEPLOY.md` is written; no relay has ever been deployed, and the app ships
  pointing at a placeholder address it says it cannot use.

## Residual risks (accepted, not hidden)

- **Traffic analysis.** The relay sees which IP polls which capability ids and when, and
  the sizes of blobs. It can infer that some devices share a channel without reading it.
- **The drain signature names a key.** Draining a mailbox presents the drainer's ed25519
  public key to the relay so it can verify the request. Over time the relay could
  correlate drains by key and IP. Presence and the graph stay protected.
- **Endpoint compromise.** Porch cannot protect a phone an attacker already controls.
- **The web preview** keeps keys in browser storage. Browser storage is shared by every
  page on the same origin, and the fleet site's build carries a porch web build beside
  the other apps: served from that shared origin, any page there could read porch's web
  keys. The rule is that porch's web build is never served from a shared origin, only
  from one of its own; until it has one, there is no public porch web build. Its
  `index.html` carries a Content-Security-Policy that runs only porch's own script files
  (no inline script) and WebAssembly; a headless Chromium load of the build showed no
  violation, and without `style-src 'unsafe-inline'` the engine's own styles were
  refused, which is why that one is there. Treat the web preview as a demo, as its
  on-screen notice says.
- **Nothing here has run on a device.** Keystore behaviour, the libsodium runtime on
  Android, and the share sheet are unverified on hardware.

## Not built (so not claimed)

- **Push.** v1 has none: `NoopPush` is the only implementation and a test fails if
  anything FCM-shaped is imported. Nothing tells Apple or Google anything.
- **Background refresh and the home-screen widget.** The app polls every 25 s while it is
  open, and nothing runs in the background.
- **Local notifications.** The choice of whom to watch is stored and the diff logic is
  tested, but no notification is shown yet.
- **A deployed relay**, and so any hosting or jurisdiction choice.

## What to verify before you trust this

The code was written by an AI assistant; treat these claims as hypotheses to check:

- **Blindness:** `relay/internal/api/privacy_test.go`, then read `channels.go` and
  `mailbox.go` for anything that parses a blob.
- **No identity on the channel plane:** the STRUCTURAL test in
  `app/test/data/api_client_test.dart`.
- **No logs:** `go test ./...` in `relay/`, and `app/test/data/relayd_integration_test.dart`,
  which boots the compiled relay and counts its output bytes.
- **Rotation:** `app/test/domain/rotation_test.dart` and
  `app/test/data/removal_invite_reentry_test.dart`.
