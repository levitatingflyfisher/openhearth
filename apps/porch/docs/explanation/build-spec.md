# Porch v1 — FINAL BUILD SPEC

**Architecture:** "Capability Channels" — a keys-first blind-relay design.
**Status:** Frozen for v1 implementation. Deviations require an ADR.
**Repo root:** `/tmp/porch-blind` (monorepo: `relay/` Go, `core/` pure Dart, `app/` Flutter, `spec/`, `ops/`, `docs/`).

---

## 1. Architecture

### 1.1 The one idea

Everything derives from one root secret and one invariant.

- **The root:** a 16-byte device entropy (shown once as a 12-word BIP39 mnemonic), expanded to a
  32-byte KDF root, from which libsodium `crypto_kdf` derives the Ed25519 identity signing key and
  the X25519 identity box key. Nothing else about identity exists anywhere.
- **The invariant:** the server routes only by unguessable capabilities derived from keys it does
  not hold. Each group has a random 256-bit symmetric key with an epoch counter; the group's wire
  address (`channelId`) and per-member presence slots are KDF-derived **from that key** — so key
  rotation on membership change simultaneously revokes decryption ability AND the routing address
  for the departed member, with zero server cooperation and zero server knowledge of membership.

### 1.2 The two planes (both anonymous at rest)

| Plane | Addressed by | Authenticated by | Carries |
|---|---|---|---|
| **Channel plane** (`/v1/ch/*`) | `channelId` = KDF(groupKey) | Knowledge of the 256-bit capability. No user auth, ever. Client structurally forbids identity headers on these paths. | Presence ciphertext (TTL'd slots) + bulletin ciphertext (roster ops, escrows, rotation duplicates) |
| **Mailbox plane** (`/v1/mailbox/*`) | `mailboxId` = hash(sign_pk) | **POST: unauthenticated** (rate-limited, size-capped, depth-capped). **Drain: stateless signed request** — Ed25519 over `porch-drain\|{mailboxId}\|{ts}`, ±300 s freshness, replay cache. No sessions, no tokens, no challenge flow. | Sealed-box rotation grants and re-grants |

There is **no session plane** (graft from "One Lamp"): no challenge endpoint, no session tokens, no
30-day server-side session state, no WebSocket hub. The server never binds a public key to an IP
session, and — because mailbox POST is anonymous — a live-compromised server cannot attribute
rotation fan-outs as pk-level sender→recipient social-graph edges. At full compromise the server
holds: anonymous public-key hashes, opaque TTL-expiring ciphertext keyed by random-looking
capabilities, and no stored link between the two. The PRD's compromise table is satisfied
structurally.

### 1.3 Transport: HTTPS polling only

Presence changes on a minutes-to-hours scale (default expiry 1 h). v1 transport is:

- **25 s polling while the feed is visible**, fetch on app open, pull-to-refresh.
- **Background:** Android WorkManager periodic (~15 min floor) + one-shot flush after widget
  toggle; iOS BGAppRefresh best-effort.
- **No WebSocket, no SSE, no FCM/APNs push in v1.** Push is reintroduced in v1.1 behind the
  client-side `PushPort` (compile-time `NoopPush` is the only v1 implementation), so de-Googled /
  GrapheneOS builds are structurally push-free and first-class. The keyring still *derives* a push
  topic from the group key (dormant), so v1.1 needs no protocol change.

### 1.4 Honesty is typed, privacy is CI-tested

- `PresenceSnapshot` **cannot be constructed without `fetchedAt`** (required constructor arg, no
  default). Feed and widget both render from it; anything older than 15 min renders
  "as of N min ago". A widget test asserts no presence-rendering widget builds without it.
- CI carries a **zero-logging grep test** (no `log.`/`slog.`/`fmt.Print*` in relay handler
  packages) and a **privacy conformance test** (every stored blob is byte-identical to the
  submitted ciphertext — the relay provably never parses).
- **On-device metrics only:** same-day re-availability is computed locally, shown only to the
  user; a dismissible "How's Porch working for you?" prompt every 30 days. No analytics plane
  exists to grow into wallpaper.

### 1.5 Stack decisions (the four PRD gates + two more, each gets an ADR)

| Decision | Choice |
|---|---|
| Gate 1: backend | **Custom Go relay** (stdlib `net/http`, ~1,500 LoC, one binary). Zero-logging must be ours to enforce structurally, not Supabase's policy promise. Redis 7 behind a `Store` interface with an in-memory fake (test suite needs no services). Hetzner Finland VM: systemd + Caddy (`log off`) + Redis (AOF everysec). |
| Gate 2: widget | **`home_widget` + `workmanager`, spiked in W1** before any presentation code hardens. Widget is a progressive enhancement: app is complete without it; the mirror port has a no-op impl. |
| Gate 3: recovery | **Seed-first: 12-word BIP39 mnemonic** (16 B entropy — 128-bit security matches Ed25519's actual level; halves the scariest onboarding moment) + **Argon2id PIN-encrypted backup blob** (seed + group-credentials snapshot) saved to user-chosen cloud/file storage. Passkey is a v2 **additive** wrapper (WebAuthn PRF immaturity on Android; PRD pre-authorizes seed fallback). GrapheneOS users are first-class day one. |
| Gate 4: invite edge | **Group-encrypted escrow of the invite token** on the channel bulletin (pinned, cannot be ring-evicted) so *any current admin* can fulfill an orphaned invite; terminal fallback is a visible **"void — regenerate"** invite state (one tap by anyone). |
| Crypto | **`sodium` + `sodium_libs` (Skycoder42), pinned exact.** `flutter_sodium` (named in PRD) is unmaintained. The `sodium` core package is Flutter-free, so `core/` tests run under plain `dart test` against the host's real `libsodium.so`. Fallback (pure-Dart `cryptography`) is documented, unaudited, and must never be silently swapped. Day-0 kill-the-risk spike before any code. |
| Client storage | **No SQLCipher, no Drift.** Secrets (seed, state key) in `flutter_secure_storage` (Keystore/Keychain); everything else in **one versioned JSON state file encrypted with XChaCha20-Poly1305** under the state key. Total state is kilobytes for 15 friends; the social graph stays encrypted at rest without a native SQL dependency. Widget snapshot is a minimal plaintext JSON in the `home_widget` shared container (accepted device-local exposure, kept tiny). |

### 1.6 Threat model (honest residuals, named)

Protected structurally: content, identity↔group linkage, social graph at rest, contact info
(never leaves devices in plaintext), usage logs (none exist).

Accepted residuals (documented in `docs/explanation/threat-model.md`, no false Tor/mixnet
promises):
- **IP/timing correlation** at the relay (which IPs poll which channelIds). PRD-accepted.
- **Rotation fan-out timing**: N near-simultaneous anonymous mailbox POSTs allow probabilistic
  co-membership inference by a live-compromised server. Mitigation: 0–30 s random jitter between
  fan-out posts. "Social graph: nothing" means nothing **stored**; timing inference is possible.
- **Intra-group vandalism**: any capability holder (member, or link thief) can stomp presence
  slots or post garbage. Garbage fails signature verification client-side and is dropped; stomping
  is bounded by rotation. Groups are "people who already love you."
- **Invite-link secrecy is the trust root**: whoever redeems the link within 72 h joins as "Bob"
  (one-time consumption; roster shows the join; admin removes + rotation fixes).
- **Ghost members** (uninstall without leave) hold the epoch key until an admin removes them.
- **Losing seed AND backup = permanent identity loss.** No server-side recovery exists BY DESIGN;
  onboarding says so plainly.

---

## 2. Module map

```
/tmp/porch-blind/
├── README.md                        # what Porch is, quickstart, links into docs/
├── HONEST-STATUS.md                 # real/tested vs stubbed vs cut — updated in the same PR as any claim
├── docker-compose.yml               # redis (AOF everysec) + relayd + caddy (log off)
├── spec/
│   └── vectors/                     # cross-language JSON test vectors, byte-exact in BOTH suites
│       ├── kdf_vectors.json         # entropy→root→keypairs, channelId/slotId/mailboxId derivations
│       ├── envelope_vectors.json    # sign-then-encrypt round-trips + tamper cases
│       ├── invite_transcript.json   # full invite handshake, incl. escrow fulfillment
│       └── rotation_transcript.json # remove→rotate, leave→successor-rotates, race tiebreak
│
├── relay/                           # Go 1.25, stdlib net/http only
│   ├── go.mod
│   ├── cmd/relayd/main.go           # flags: -addr, -store=memory|redis, -redis-url; graceful shutdown; stderr startup errors only
│   └── internal/
│       ├── store/
│       │   ├── store.go             # Store interface — every write carries a TTL; no TTL-less write exists
│       │   ├── memstore.go          # in-memory impl + injectable clock (powers the whole unit suite)
│       │   ├── redisstore.go        # SET EX / RPUSH / INCR / atomic consume via SET NX + Lua where needed
│       │   └── conformance_test.go  # ONE suite, both impls; Redis leg gated on REDIS_URL (docker-compose)
│       └── api/
│           ├── router.go            # mux + middleware: rate limits, size caps; ZERO logging calls
│           ├── invites.go           # create / join(atomic consume) / proof-gated fetch / grant / grant-fetch+delete
│           ├── invites_test.go      #   incl. N-concurrent-join race → exactly one 204
│           ├── mailbox.go           # anonymous POST (caps), stateless signed drain (atomic returned==deleted)
│           ├── mailbox_test.go
│           ├── channels.go          # presence post/get (TTL'd slots), bulletin post/get (server seq, pinned entries)
│           ├── channels_test.go
│           ├── sigauth.go           # Ed25519 drain verification: freshness ±300s + replay cache (~60 lines)
│           ├── sigauth_test.go
│           ├── ratelimit.go         # per-IP token buckets, in-memory
│           ├── ratelimit_test.go
│           └── privacy_test.go      # stored-blob==submitted-blob byte-identity + no-logging grep test
│
├── core/                            # pure-Dart package `porch_core` — NO Flutter imports anywhere
│   ├── pubspec.yaml                 # deps: sodium (pinned exact); dev: test
│   ├── lib/porch_core.dart
│   ├── lib/src/
│   │   ├── mnemonic.dart            # BIP39 12-word encode/decode of 16B entropy (encoding only, not crypto)
│   │   ├── identity.dart            # entropy→root→Ed25519+X25519 keypairs, mailboxId, backup-blob format
│   │   ├── keyring.dart             # epoch keys; channelId/slotId/pushTopic(dormant) derivation; grace policy (encrypt newest, decrypt last 2, 7d prune)
│   │   ├── envelope.dart            # sign-then-encrypt wire codec, AD binding, size caps — the ONLY module touching network-bound plaintext
│   │   ├── roster.dart              # signed ops (JOIN/REMOVE/LEAVE/TRANSFER_ADMIN/PROFILE), deterministic fold, admin succession
│   │   ├── invite.dart              # token/proof derivations, join/grant blob construction+verification, escrow record, state machine incl. `void`
│   │   ├── rotation.dart            # triggers, rotator election, grant bundles, seq-ordered adoption + deterministic tiebreak fallback, rekey-request self-heal
│   │   ├── snapshot.dart            # PresenceSnapshot{entries, fetchedAt REQUIRED}; feed fold (verify→dedupe→drop-expired)
│   │   ├── protocol.dart            # typed relay request/response codecs + drain-signature construction (shared by app + sim)
│   │   └── sim/
│   │       ├── sim_relay.dart       # in-memory relay implementing exact server semantics (incl. seq, atomic consume)
│   │       └── sim_device.dart      # a full simulated client for two-device protocol tests
│   └── test/                        # one _test.dart per module + transcript tests consuming ../spec/vectors
│
├── app/                             # Flutter (Android first; iOS best-effort)
│   ├── pubspec.yaml                 # sodium_libs, flutter_riverpod, flutter_secure_storage, http, home_widget, workmanager — ALL pinned exact
│   ├── lib/
│   │   ├── main.dart
│   │   ├── bootstrap.dart           # sodium_libs init, DI wiring of ports → porch_core
│   │   ├── data/
│   │   │   ├── api_client.dart      # typed HTTP client; STRUCTURALLY no identity material on /v1/ch/* (unit-tested)
│   │   │   ├── key_store.dart       # flutter_secure_storage: seed entropy + state-file key
│   │   │   ├── state_store.dart     # versioned encrypted JSON state file (XChaCha20-Poly1305), atomic write+rename
│   │   │   ├── group_repo.dart      # groups, rosters, epoch keys, folded state
│   │   │   ├── presence_repo.dart   # optimistic outbox-first tap path: local flip renders instantly, network never blocks
│   │   │   ├── invite_repo.dart     # mint/redeem/fulfill/void—regenerate lifecycle
│   │   │   ├── sync_service.dart    # RefreshFeed: poll channels (+grace) → bulletin fold by seq → signed drain → snapshot(fetchedAt) → mirror → notify-diff
│   │   │   ├── notification_service.dart # per-friend/per-group opt-ins, LOCAL notifications only, OFF by default
│   │   │   ├── metrics_service.dart # on-device same-day re-availability + 30-day dismissible prompt state
│   │   │   ├── push_port.dart       # PushPort interface + NoopPush (the only v1 impl; FCM adapter is v1.1)
│   │   │   └── widget_cache.dart    # WidgetCacheMirror port: home_widget kv writer + NoopMirror
│   │   ├── background/
│   │   │   ├── scheduler.dart       # WorkManager periodic + one-shot flush; iOS BGAppRefresh registration
│   │   │   └── widget_callback.dart # Android background Dart entrypoint: widget long-press → PublishStatus via outbox
│   │   └── presentation/
│   │       ├── providers.dart       # Riverpod: identity, groups, feed ticker, staleness, invite states
│   │       ├── onboarding/          # age gate (13+) → silent keygen → 12-word reveal → backup offer → display name → "My Porch"
│   │       ├── home/                # big Available button (group multi-select, 30m/1h/2h/4h/manual, tag presets+custom), feed w/ countdown + staleness line
│   │       ├── groups/              # list + detail: roster, tap-a-friend (name+contact note), invite lifecycle incl. "void — regenerate", remove/transfer, silent leave
│   │       ├── join/                # porch:// handler + paste-the-code box (primary tested path)
│   │       └── settings/            # profile (name/contact note), seed re-reveal, backup, notify opt-ins, "Your Porch stats", "What leaves your device"
│   ├── test/                        # honesty widget test, optimistic-tap test, goldens 320dp textScale 1–3
│   ├── android/                     # AppWidget provider + Glance/RemoteViews rendering from shared container
│   └── ios/                         # WidgetKit timeline from App Group + AppIntent pending-flag (best-effort)
│
├── ops/
│   ├── Caddyfile                    # TLS, `log off` — part of the audited surface
│   ├── porchd.service               # systemd unit
│   └── DEPLOY.md                    # Hetzner Finland notes; docker-compose reproduces prod locally
│
└── docs/                            # Diátaxis hub (final work package)
    ├── README.md
    ├── tutorials/  how-to/  reference/  explanation/ (threat-model.md lives here)
    └── adr/
        ├── 0001-custom-go-relay-over-supabase.md
        ├── 0002-sodium-libs-pinned-ffi-crypto.md
        ├── 0003-seed-first-12-word-recovery.md
        ├── 0004-invite-escrow-and-void-regenerate.md
        ├── 0005-polling-only-no-push-no-websocket-v1.md
        ├── 0006-stateless-signed-drain-no-session-plane.md
        └── 0007-encrypted-json-state-no-sqlcipher.md
```

---

## 3. Crypto flows (step-by-step)

All primitives are libsodium; the only home-made layer is message framing. Canonical JSON
(sorted keys, no whitespace) is the signing/encryption input everywhere.

### 3.1 Identity & recovery

1. First launch: `entropy = randombytes(16)`.
2. Mnemonic: 12 BIP39 words = encode(entropy) — encoding only; shown once at onboarding,
   re-revealable in Settings.
3. Root: `root = crypto_generichash(out=32, msg=utf8("porch/root/v1") ‖ entropy)`.
4. Keypairs via `crypto_kdf_derive_from_key(root, subkey_id=1, ctx=…)`:
   - `ctx="PORCHSGN"` → 32 B seed → `crypto_sign_seed_keypair` → **Ed25519 identity** (sign_pk, sign_sk).
   - `ctx="PORCHBOX"` → 32 B seed → `crypto_box_seed_keypair` → **X25519 identity** (box_pk, box_sk).
   Independent derivation; no Ed→X conversion.
5. `mailboxId = base64url(crypto_generichash(out=32, msg=utf8("porch/mbox/v1") ‖ sign_pk))`.
6. Storage: `entropy` in Keystore/Keychain. The server never learns sign_pk until first drain,
   and never links it to any group.
7. **Backup blob** (optional, PIN-protected, written to user-chosen cloud/file storage;
   opportunistically re-written on membership/epoch change):
   `salt = randombytes(16)`; `bk = crypto_pwhash(out=32, PIN, salt, MODERATE, Argon2id13)`;
   `blob = header{v:1, salt, opslimit, memlimit} ‖ crypto_aead_xchacha20poly1305_ietf_encrypt(key=bk, nonce=random24 prefixed, plaintext={entropy, stateSnapshot})`.
   `stateSnapshot` includes groups, epoch keys, and rosters → **full restore**.
8. **Recovery paths** (both truthfully surfaced in UX):
   - Backup blob + PIN → full restore (identity + groups), then drain mailbox + refresh.
   - 12 words alone → identity only; because the server holds no pk→group mapping BY DESIGN,
     groups return via the rekey-request self-heal (if roster peers still list you) or fresh
     invites from friends.

### 3.2 Group creation & key lifecycle

1. Create group (incl. auto-created "My Porch" at onboarding): mint locally
   `groupUuid` (client-only, server NEVER sees it), `gk_1 = randombytes(32)` (epoch 1),
   roster `[self]`, self is admin. **No server call exists for group creation** — a group is a
   purely client-side fact.
2. Derivations from `gk_e` (all via `crypto_kdf`/`crypto_generichash`):
   - `channelId_e = base64url(crypto_kdf_derive_from_key(gk_e, 1, "PORCHCHN"))` — the wire
     address; knowledge of it IS membership proof.
   - `slotKey_e = crypto_kdf_derive_from_key(gk_e, 1, "PORCHSLT")`;
     `slotId_m = base64url(crypto_generichash(out=16, msg=member_sign_pk, key=slotKey_e))` —
     server can replace-per-member without knowing who a member is.
   - `writerId_m = base64url(crypto_generichash(out=16, msg="porch/bulletin-writer/v1" ‖ member_sign_pk, key=gk_e))` —
     names a bulletin's writer so a second writer confirms the channel; it shares nothing
     with `slotId_m`, so the server cannot tie a member's bulletins to their presence.
   - `pushTopic_e = crypto_kdf_derive_from_key(gk_e, 1, "PORCHTPC")[0:12]` — **dormant in v1**
     (derived + vector-tested so v1.1 push needs no protocol change).
3. Key policy: encrypt with newest epoch only; retain last 2 epochs for decrypt; prune retired
   epochs after 7 days.

### 3.3 Envelope (one codec for every channel payload)

```
payload    = canonical JSON {v:1, type, ...fields, issuedAt, epoch, senderSignPk}
sig        = crypto_sign_detached(payload, sign_sk)
wire       = nonce(24B) ‖ crypto_aead_xchacha20poly1305_ietf_encrypt(
               key = gk_epoch,
               nonce = random 24B,
               ad  = utf8("porch/v1") ‖ channelId ‖ epoch_le64,
               msg = canonical JSON {payload, sig})
```
Receivers: decrypt (try newest epoch, then grace epoch) → verify `sig` against `senderSignPk` →
verify `senderSignPk` is in the local roster → else DROP silently. A compromised server (or
vandal) can inject garbage but can never forge a friend.

### 3.4 Presence: encrypt → route → TTL

1. **Tap Available** (app button or Android widget long-press): user picks group(s) (default
   broadcast set remembered), expiry (30 m/1 h/2 h/4 h/manual; default 1 h), optional tag
   (presets 🚶🧹🚗💻📖 + short custom). **Optimistic outbox-first:** local state flips and
   renders instantly; the encrypted event is queued and drained with retry — the tap path never
   blocks on network.
2. Event: `type:"presence", status:"on", tag, issuedAt, expiresAt` → envelope under current
   epoch → `POST /v1/ch/{channelId}/presence {slotId, blob, ttlSec = expiresAt−now (≤14700)}`
   per selected group.
3. Server: `SET p:{channelId}:{slotId} = blob EX ttlSec` — overwrite = status update/extend.
   Presence **structurally cannot exist after expiry** (native Redis TTL, not soft-delete).
4. **Manual off:** overwrite own slot with a signed `status:"off"` event, `ttlSec=60` — pollers
   drop the row within one cycle; then the tombstone evaporates. No delete endpoint needed.
5. **Feed refresh** (25 s foreground / on-open / pull-to-refresh / background):
   for each group → GET presence on current channelId (+ previous channelId during the 7-day
   grace) → GET bulletin `afterSeq` → fold ops in seq order → signed mailbox drain → apply
   rotation grants → decrypt/verify/dedupe (keep highest `issuedAt` per member, drop expired,
   drop unverifiable) → persist `PresenceSnapshot(entries, fetchedAt: now)` → mirror widget
   cache → run local notification diff.
6. Feed renders name, tag, time remaining (countdown from `expiresAt`), and the staleness line
   whenever `fetchedAt` > 15 min old. Tap a friend → display name + preferred-contact note from
   the roster. No read receipts — the protocol cannot express them (reads are capability-GETs
   with no identity attached).

### 3.5 Invite handshake (trust rooted in the link; PRD gate 4 handled)

Derivations from token `t = randombytes(32)` (all `crypto_generichash(out=32, key=t, msg=…)`):
`inviteId = base64url(gh(msg="porch/inv/id/v1"))[0:22]`, `k_i = gh(msg="porch/inv/key/v1")`,
`fetchProof = gh(msg="porch/inv/fetch/v1")`, `grantProof = gh(msg="porch/inv/grant/v1")`.

1. **Alice mints:** generates `t`; link = `porch://i#<inviteId>.<base64url(t)>` — the token
   rides the fragment / pasted code and **never touches the server**; only `inviteId` is
   registered: `POST /v1/invites {inviteId, ttlHours ≤ 72}` (one-time, rate-limited).
2. **Escrow (inviter-left insurance):** Alice posts a **pinned** bulletin envelope
   `type:"ESCROW" {t, inviteId, expiresAt}` encrypted under `gk` — so any current member with
   admin rights can complete the handshake if Alice leaves. Pinned entries cannot be ring-evicted
   and expire with the invite TTL.
3. **Bob joins:** onboards (own seed, no server contact needed yet), taps link or pastes code,
   computes `inviteId`/`k_i`, posts
   `POST /v1/invites/{id}/join {blob = crypto_secretbox(k_i, {boxPk, signPk, displayName, contactNote})}`.
   Server atomically flips open→joined (`SET NX`); a second taker gets **410**. The server stores
   the join blob but cannot read it and never learns Bob's keys.
4. **Fulfillment** (Alice, or an admin who decrypted `t` from escrow):
   `GET /v1/invites/{id}/join?proof=fetchProof` (computable only with `t`, which the server never
   had) → decrypt intro → add Bob to roster → post grant:
   `POST /v1/invites/{id}/grant {proof: fetchProof, blob = crypto_box_seal(bobBoxPk, {groupUuid, groupName, epoch, gk_e, signedRoster, granterSignPk, granterSig})}`.
   The server cannot forge a grant (doesn't know Bob's box_pk) nor read it.
5. **Bob completes:** `GET /v1/invites/{id}/grant?proof=grantProof` → server returns the blob and
   **deletes it after retrieval** (PRD). Bob verifies granterSig against the delivered signed
   roster (TOFU rooted in the out-of-band link — stated, not hidden), stores `gk`, derives
   `channelId`, starts polling.
6. **Join announce:** the fulfiller posts a signed `JOIN` roster op to the bulletin; members see
   "Bob joined My Porch" as a **passive banner on next open** — never a popup. **Joins do NOT
   rotate keys** (PRD: departures only). Bob can read presence ciphertext still live from the
   last ≤4 h — accepted, bounded by presence TTL, documented.
7. **Terminal fallback:** if fulfillment is impossible (inviter gone AND no admin online before
   TTL, or escrow lost), the invite row in GroupDetail shows **"void — regenerate"** — one-tap
   regeneration by anyone. This is the universal recovery; no deeper machinery exists.

### 3.6 Rotation on membership change (remove / leave — the PRD's key rotation)

1. **Triggers:** admin posts signed `REMOVE{memberPk}`; or leaver posts signed `LEAVE` to the
   bulletin then wipes local keys (silent — clients fold it without rendering any notification,
   ever). Uninstall-without-leave is covered by admin removal.
2. **Rotator election (deterministic, client-side, no server):** current admin. If the admin is
   the one departing: **oldest remaining member by roster `joinedAt`, ties broken by smallest
   sign_pk (lexicographic bytes)** — every client computes the same successor, who also becomes
   admin (PRD admin-succession rule; same rule, one implementation in `roster.dart`).
3. **Rotator acts:** mints `gk_{e+1} = randombytes(32)`; for each remaining member posts to their
   mailbox (mailboxIds computed from roster sign_pks; **anonymous POSTs** with 0–30 s jitter):
   `crypto_box_seal(member_boxPk, {groupUuid, epoch e+1, gk_{e+1}, updatedSignedRoster, rotatorSignPk, rotatorSig})`.
   A **duplicate bundle rides the OLD channel bulletin** (outer envelope under `gk_e`, inner
   per-member sealed boxes) as a latency optimization — the departed member can open the outer
   envelope but not the inner boxes.
4. **Adoption rule (server seq makes ordering total; tiebreak is only a fallback):**
   - Validate: rotatorSig verifies; rotator is the admin per the post-departure roster, or the
     deterministic successor when the admin departed. Re-grants of an *existing* epoch
     (self-heal) may come from any roster member.
   - Among valid competing bundles for the same new epoch: **lowest bulletin `seq` wins**
     (server-assigned, monotonic per channel). Mailbox-only bundles with no seq: admin-authored
     wins, else smallest `crypto_generichash(gk_{e+1})`. Property-tested: any delivery order →
     identical final epoch/key on every member.
5. **Effect:** members adopt e+1, derive the NEW channelId, switch polling and posting
   immediately. The departed member loses the key AND the channel address in one stroke — they
   cannot even fetch ciphertext; old-channel slots die by TTL within ≤4 h. Old epoch stays
   decrypt-only for 7 days (stragglers' events still render). **Honest window:** events posted
   under the old epoch by not-yet-rotated members remain readable by the departed member until
   those members rotate — bounded by presence TTL, documented.
6. **Self-heal:** a member who missed rotation blobs (mailbox cap/TTL, wiped Redis) posts a
   signed sealed `REKEY_REQUEST` on the old channel bulletin; any current member re-grants the
   current epoch via mailbox. This path is integration-tested against a wiped store before ship.

### 3.7 Admin ops & profile updates

- `TRANSFER_ADMIN{toPk}` — signed by current admin, bulletin op, no rotation.
- `REMOVE{memberPk}` — admin-only, triggers rotation (3.6).
- `PROFILE{displayName?, contactNote?}` — signed by the member, posted to **each of their
  groups' bulletins** (the global contact field fans out per group envelope); folds into rosters.
- Roster fold is deterministic: ops ordered by (bulletin seq), signer authority checked per op
  type; fold is idempotent and property-tested.

---

## 4. Server API

Base `/v1`. All bodies JSON; blobs base64. All writes TTL'd. Per-IP token-bucket rate limits and
hard size caps on everything. Errors are status codes only — no echoed bodies, no logging.
Two auth mechanisms only: **knowledge capabilities** (unguessable ids over TLS) and **one
stateless signature** (mailbox drain). No accounts, no sessions, no tokens.

| # | Method & path | Auth | Request | Response |
|---|---|---|---|---|
| 1 | `POST /v1/invites` | none (rate-limited: ≤50/day/IP) | `{inviteId, ttlHours ≤72}` | `201 {expiresAt}` · `409` if id exists |
| 2 | `POST /v1/invites/{id}/join` | capability: inviteId | `{blob ≤8KiB}` | `204`; atomic open→joined (`SET NX`) · `410` used/expired · `404` unknown |
| 3 | `GET /v1/invites/{id}/join?proof=` | capability: `fetchProof` (derivable only from `t`) | — | `200 {blob}` · `404/410` |
| 4 | `POST /v1/invites/{id}/grant` | capability: `fetchProof` | `{proof, blob ≤16KiB}` | `204` |
| 5 | `GET /v1/invites/{id}/grant?proof=` | capability: `grantProof` | — | `200 {blob}` then **grant blob deleted** (delete-after-retrieval) · `404` |
| 6 | `POST /v1/mailbox/{mailboxId}` | **none** (anonymous by design; rate-limited/IP) | `{blob ≤8KiB}` | `204`; RPUSH, depth cap 200 → `429 mailbox full`; list TTL refreshed to 30 d |
| 7 | `POST /v1/mailbox/{mailboxId}/drain` | **stateless signed**: body carries `{pubkey, ts, sig}`; server checks `hash(pubkey)==mailboxId`, `sig = crypto_sign_detached("porch-drain\|"+mailboxId+"\|"+ts)`, `\|now−ts\| ≤ 300s`, replay cache on `hash(sig)` (10 min) | `{pubkey, ts, sig}` | `200 {blobs:[…]}` — **atomic: returned == deleted** (LPOP-count) |
| 8 | `POST /v1/ch/{channelId}/presence` | capability: channelId (identity headers structurally absent) | `{slotId, blob ≤1KiB, ttlSec ≤14700}` | `204`; `SET p:{ch}:{slot} EX ttlSec` (overwrite = update/extend) |
| 9 | `GET /v1/ch/{channelId}/presence` | capability: channelId | — | `200 {slots:[{slotId, blob, expiresAt}]}` — only unexpired keys can exist |
| 10 | `POST /v1/ch/{channelId}/bulletin` | capability: channelId | `{slotId (the writer's per-epoch bulletin writer id, optional), blob ≤8KiB, pinned:bool, ttlSec ≤259200 (pinned only)}` | `200 {seq}` — **server-assigned monotonic seq per channel** (Redis INCR); unpinned → ring of last 8 (60 d sliding); pinned → own TTL ≤72 h, cap 16/channel, never ring-evicted |
| 11 | `GET /v1/ch/{channelId}/bulletin?afterSeq=N` | capability: channelId | — | `200 {entries:[{seq, blob, pinned, expiresAt?}]}` ordered by seq |
| 12 | `GET /v1/healthz` | none | — | `200` (unlogged, like everything else) |

**What does not exist:** group create/list/delete (groups are client-side facts — no group
registry, no member table, no join table), sessions/challenges, WebSocket/SSE, push-token
registry, user records of any kind. Caddy terminates TLS with `log off`; the relay binary
contains zero logging calls (CI-greped); the Caddyfile is part of the audited surface.

---

## 5. Client data model

### 5.1 Secure storage (Keystore / Keychain via `flutter_secure_storage`)

| Key | Value |
|---|---|
| `porch.entropy.v1` | 16 B identity entropy (hex) |
| `porch.statekey.v1` | 32 B state-file encryption key |

### 5.2 Encrypted state file (`state.v1.enc` — XChaCha20-Poly1305 under statekey, atomic write+rename)

```jsonc
{
  "v": 1,
  "profile":  { "displayName": "", "contactNote": "" },          // plaintext exists ONLY here and inside E2EE envelopes
  "groups": [{
      "groupUuid": "", "name": "", "epoch": 3, "adminPk": "", "myRole": "admin|member",
      "keys":   [{ "epoch": 3, "gk": "b64" }, { "epoch": 2, "gk": "b64", "retiredAt": 0 }],  // newest encrypts; last 2 decrypt; 7d prune
      "roster": [{ "signPk": "", "boxPk": "", "displayName": "", "contactNote": "", "joinedAt": 0, "isAdmin": false }],
      "pendingInvites": [{ "inviteId": "", "t": "b64", "expiresAt": 0, "state": "open|joined|granted|void" }],
      "lastBulletinSeq": { "channelId": 42 },
      "defaultBroadcast": true
  }],
  "presence": {                                                   // PresenceSnapshot per group — fetchedAt is REQUIRED by the type
      "<groupUuid>": { "fetchedAt": 0, "entries": [{ "memberSignPk": "", "tag": "", "issuedAt": 0, "expiresAt": 0 }] }
  },
  "outbox":   [{ "id": "", "op": "presence|bulletin|mailbox|invite", "payload": {}, "attempts": 0, "createdAt": 0 }],
  "notifyPrefs": { "perFriend": {}, "perGroup": {} },             // ALL default off; local only — server never learns who watches whom
  "settings": { "defaultExpiry": 3600, "customTags": [] },
  "metrics":  { "days": [{ "date": "2026-07-10", "publishes": 2, "firstAt": 0, "lastAt": 0 }] },  // on-device only, never transmitted
  "feedback": { "lastPromptAt": 0 }
}
```

### 5.3 Widget cache contract (progressive enhancement)

`home_widget` shared container (App Group / SharedPreferences), plaintext by necessity, kept
minimal — the accepted device-local exposure:

```json
{ "schema": 1, "availableCount": 2,
  "top3": [{ "name": "Sarah", "tag": "walking", "expiresAt": 0 }],
  "fetchedAt": 0 }
```

Contract: (a) the widget renders **only** from this cache; (b) it always renders `fetchedAt`
staleness when >15 min old ("Sarah was available 23 min ago") — never blank, never silently
stale; (c) tap opens the feed; (d) **Android long-press** toggles availability via a background
Dart callback executing the PublishStatus use case through the outbox (+ one-shot WorkManager
flush); **iOS** uses an AppIntent pending-flag + deep-link fallback — the platform limit is
stated in HONEST-STATUS.md; (e) `WidgetCacheMirror` has a no-op implementation — deleting the
widget touches nothing else. The app is complete without it.

### 5.4 Server data model (Redis only — every key TTL'd at write; no TTL-less write path exists)

| Key | Value | TTL |
|---|---|---|
| `inv:{inviteId}` | `{state: open\|joined, joinBlob?, grantBlob?}` | ≤72 h (grantBlob field deleted after retrieval; record kept for honest 410s) |
| `mbox:{mailboxId}` | LIST of blobs (cap 200) | 30 d rolling |
| `p:{channelId}:{slotId}` | presence blob | = status TTL, ≤14700 s |
| `b:{channelId}` | ring of 8 `{seq, blob}` | 60 d sliding |
| `bp:{channelId}:{seq}` | pinned blob | ≤72 h own TTL, cap 16/channel |
| `seq:{channelId}` | INCR counter | 60 d sliding |
| `rl:{ip}:{bucket}` | token-bucket counters | 60 s |
| `replay:{sigHash}` | drain replay guard | 10 min |

Redis AOF everysec. Total loss degrades gracefully: undelivered mail + live statuses vanish;
groups recover via the rekey-request self-heal (explicit integration test). No Postgres, no
migrations, no backups containing user data.

---

## 6. Work packages W1–W5 (TDD throughout: failing test first, every module lands with its tests; HONEST-STATUS.md updated in the same PR as any claim it covers)

### W1 — Spikes + crypto foundation (`core/` part 1)
Scope: repo skeleton; **Day-0 kill-the-risk spikes** — (a) `sodium` on Dart VM against host
libsodium + `sodium_libs` init on an Android emulator, (b) `home_widget` hello-world render +
background callback on Android (PRD gate 2 — widget claims shrink to match reality if this
disappoints); then `mnemonic.dart`, `identity.dart`, `keyring.dart`, `envelope.dart`; seed
`spec/vectors/` as tests pass.
**Acceptance tests:**
- 12-word mnemonic round-trip; same words twice → byte-identical keypairs (determinism).
- KDF vectors: entropy→root→sign/box keypairs, mailboxId, channelId/slotId/pushTopic derivations — committed to `spec/vectors/kdf_vectors.json`.
- Envelope round-trip; AD tamper → reject; wrong epoch → reject; forged/absent signature → reject; grace-epoch decrypt works; epoch-prune policy honored.
- Backup blob: encrypt/restore round-trip; wrong PIN fails cleanly.
- Both spikes have written pass/fail notes in HONEST-STATUS.md.

### W2 — Protocol state machines (`core/` part 2)
Scope: `roster.dart`, `invite.dart`, `rotation.dart`, `snapshot.dart`, `protocol.dart`, `sim/`
(in-memory relay with exact server semantics incl. seq + atomic consume).
**Acceptance tests (two-simulated-device suite):**
- Full invite transcript: mint → escrow → join → fulfill → grant → Bob decrypts, verifies granter sig, derives channelId (→ `spec/vectors/invite_transcript.json`).
- Orphaned invite fulfilled by an admin via escrow; and the terminal path: no fulfiller → state becomes `void` (UI-visible), regenerate mints a fresh invite.
- Remove → rotate: departed member can neither decrypt epoch e+1 **nor address the new channel**; grace window renders stragglers' old-epoch events.
- Leave (silent): no notification op is ever produced; successor election — admin leaves → oldest remaining member (tie → smallest sign_pk) elected **identically on every client** (property test over shuffled rosters/timestamps).
- Concurrent-rotation convergence (property-based): any delivery order/interleaving → same final epoch and key everywhere; seq-ordered adoption primary, deterministic tiebreak fallback.
- Rekey-request self-heal: member with wiped keys regains current epoch via re-grant.
- `PresenceSnapshot` cannot be constructed without `fetchedAt` (compile-enforced; API has no default).
- Roster fold idempotence + signer-authority rejection (non-admin REMOVE rejected, non-member PROFILE rejected).

### W3 — Relay + cross-language conformance (`relay/`, `spec/`)
Scope: Store interface + memstore (injectable clock) + redisstore; all 12 endpoints; sigauth;
rate limits; caps; seq; docker-compose; integration harness.
**Acceptance tests:**
- Store conformance suite passes on memstore AND redisstore (Redis leg gated on `REDIS_URL`); `go test ./...` green with zero services.
- Every write carries a TTL (suite asserts no TTL-less write path); fake-clock advance → presence GET returns empty, invite expires, mailbox TTL refreshes.
- Invite: N concurrent joins → exactly one 204, rest 410; grant delete-after-retrieval; proof-gated fetch rejects wrong/absent proofs.
- Drain: bad sig / stale ts / wrong pubkey-hash / replayed sig → 401; atomic returned==deleted under concurrent drains; mailbox depth cap → 429.
- Bulletin: monotonic per-channel seq; ring evicts oldest unpinned only; pinned entries survive ring pressure and die by own TTL; `afterSeq` paging.
- Size caps and per-IP rate limits enforced (values are tunable constants; tests assert enforcement).
- **Privacy conformance:** stored blob byte-identical to submitted blob on every write path; **no-logging grep test** over handler packages; `api_client` structural test (no identity material on `/v1/ch/*`) mirrored Go-side by asserting no handler reads identity from channel paths.
- **Cross-language:** `go test` and `dart test` both assert `spec/vectors/*` byte-exact.
- **Integration:** harness boots the compiled relay (memstore) and drives two `porch_core` clients over localhost: onboard×2 → group → invite → join → grant → both publish → both see tag+countdown → silent leave → successor rotates → departed member locked out (cannot fetch new channel, cannot decrypt) → **wiped-store self-heal** recovers a straggler. Runs in CI with no external services.

### W4 — Flutter app: data + presentation (`app/` minus widget)
Scope: key_store, state_store, api_client, repos, sync_service, notification_service,
metrics_service, PushPort(Noop), all five screen groups, porch:// + paste-code join.
**Acceptance tests:**
- state_store: encrypt/decrypt round-trip, versioned migration hook, atomic write (kill mid-write → old state intact).
- Optimistic tap test: network down → Available flips instantly, outbox queues, drains on reconnect (fake relay).
- sync_service ordering: bulletin ops folded by seq BEFORE presence decode; rotation grant applied before next poll uses new channelId; fetchedAt set on every snapshot.
- **Honesty widget test:** no presence-rendering widget builds without a `PresenceSnapshot`; snapshots >15 min old render the staleness line ("as of N min ago").
- Notification service: **fresh install has every opt-in OFF and fires nothing**; per-friend and per-group diffs fire LOCAL notifications only; prefs never serialize into any network payload (asserted).
- Metrics: publishes recorded locally; same-day re-availability computed; nothing metric-shaped in any outbound request (asserted against fake relay); 30-day prompt dismissible state.
- Onboarding flow test: age gate (13+) → keygen → 12-word reveal → optional backup → name → "My Porch" auto-created; name/contactNote appear in no plaintext network payload.
- Invite UI states: open → joined → granted, and void → "regenerate" (one tap mints fresh).
- Goldens: Home/Feed/GroupDetail at 320 dp, textScale 1–3 (house accessibility sweep); no read-receipt affordance exists to assert absent.
- `flutter analyze` clean; never run `flutter build apk/web`.

### W5 — Widget bridge + hardening + ops + docs spine
Scope: widget_cache mirror, Android AppWidget + long-press toggle callback, iOS
WidgetKit/AppIntent best-effort, background scheduler, fan-out jitter, ops/, docs/.
**Acceptance tests:**
- Widget cache writer unit tests: exact contract JSON (§5.3), NoopMirror leaves app fully functional.
- Android background toggle: callback → PublishStatus via outbox → one-shot flush (integration-style with fake relay); iOS pending-flag path documented + manual smoke checklist in HONEST-STATUS.md.
- Background refresh: WorkManager task runs RefreshFeed and mirrors cache with fresh `fetchedAt`.
- Rotation fan-out applies 0–30 s jitter (unit-tested schedule).
- docker-compose up → healthz green; Caddyfile has `log off`; DEPLOY.md walks a Hetzner install.
- Docs spine complete: README, VISION (honest scorecard), AGENTS.md, `docs/` Diátaxis hub, ADRs 0001–0007, `docs/explanation/threat-model.md` with the residual-risk table (incl. "nothing STORED; timing inference possible") and no false Tor/mixnet promises.
- Final HONEST-STATUS.md separates real/tested vs stubbed vs cut, explicitly listing: no push, no passkey, iOS widget best-effort, single device, custom-scheme links only.

---

## 7. Out of scope for v1 (explicit)

**PRD-deferred, key model must not foreclose them:**
- **Multi-device / linked devices** — one keypair, one primary device. Rosters key on pubkey (not device), leaving the v2 door open. Documented known limitation.
- **Passkey recovery** (PRD gate 3 resolved seed-first) — v2 additive wrapper over the same seed root; forecloses nothing.
- **Push notifications (FCM/APNs silent push)** — cut from v1 (the PRD itself calls push "a convenience layer"); the Google-visible topic-membership leak exceeds the PRD's accepted "a push was delivered". Returns in v1.1 behind the compile-time `PushPort` flavor; pushTopic derivation already exists dormant. Notifications meanwhile ride background fetch + on-open (a PRD-sanctioned degraded mode).
- **Deep links / platform calling matrix** (`signal://`, `facetime://`, …) — contact note is a text field, period. Also: https universal/app links for invites (needs domain + flaky messenger handling); v1 ships `porch://` + paste-the-code as the primary tested path.
- **Per-group contact handle system** (many-to-many grants) — the single global freeform field only.
- **Scheduled availability** — conflicts with core energy; cut per PRD.
- **Foursquare-lite / meetup mode / any location** — different trust model; cut per PRD.
- **Nostr relays / blockchain anchoring** — cut per PRD (keys remain Nostr-expressible in principle).
- **Monetization machinery**: none. No donation link (the publisher's rule: never ask for donations); the Stripe capability-token path is a documented future, not code.

**Cut permanently (product values, not missing features):**
- **Read receipts / seen indicators** — the protocol cannot express them; never returning.
- **Leave notifications** — silent leave is sacred; never returning.
- **Direct "calls made" measurement / any telemetry** — on-device proxy metrics only.

**v1 engineering non-goals:**
- WebSocket/SSE realtime (polling suffices at presence timescales), server-side durability beyond Redis TTL windows, group rename (name fixed at creation; signed-op rename is a trivial v1.1 add), mailbox spam-proofing beyond caps+rate limits (invite-derived posting proofs are the flagged v1.1 answer if abused), iOS from-widget background toggle (AppIntent pending-flag + deep-link fallback only — platform limit stated in HONEST-STATUS.md).
