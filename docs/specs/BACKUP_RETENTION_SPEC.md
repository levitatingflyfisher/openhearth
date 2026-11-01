# Backup Retention & Restore-Safety Spec — sanctuaryAuth v2

*Drafted 2026-07-12, from the sourced research pass (Ink & Switch ideals;
Obsidian/Actual Budget/Time Machine restore-safety; OWASP KDF; Tink AEAD;
restic/Borg integrity). STATUS: **SHIPPED 2026-07-16** for the three-app
wave (sanctuary_backup_ui v0.2.0 + Sundial + Lullaby + PunctumTemporis;
all pushed, PWAs redeployed + boot-probed, APKs on v0-apk releases). §8
records the decisions taken at execution time after a 6-agent scout pass
re-verified this spec against the code; a 59-agent adversarial review
confirmed 51 findings (heavy overlap → ~20 unique), all fixed same-day —
headline classes: auto-pin released before durable put, index self-heal
cascading pin-loss into prune deletions, ONE SHARED OPFS vault dir across
all fleet PWAs (one origin!), adopt re-check reading cached state instead
of the keystore, settings excluded from PT's rollback. Remaining recorded
deferrals: Safari <18.4 lacks main-thread createWritable (vault
fail-closes with honest copy there), 7 non-wave repos re-lock at their
own adoption, StillLife's merge-restore needs its own rollback wording at
its adoption moment. The other six apps adopt via the
fleet-standardization campaign (plan #2).*

## 0. One-sentence thesis

Make restore boring: every restore is preceded by a mandatory automatic
snapshot, every backup is one of many stamped generations rather than a
single overwritable file, every backup can be verified and previewed before
it touches data, and every app can also emit plain unencrypted JSON because
sovereignty means you can *read* your own data, not just recover it.

## 1. What the research settled (design inputs)

1. Restore is destructive-replace everywhere (Obsidian, Actual Budget) — the
   industry safety net is NOT smarter merging, it is **generational keep-N
   timestamped backups** + **preview-before-restore**. We adopt that.
2. "Untested backups don't count" (restic/Borg) — **verify** must be a
   first-class operation, and export should self-verify by read-back.
3. AEAD + atomic single-transaction restore we already have. Keep.
4. KDF finding CORRECTED: PBKDF2-2048 over a BIP39 mnemonic is fine — the
   root is machine-generated 128-bit entropy, not a human password; OWASP's
   Argon2id/600k guidance targets low-entropy secrets. **Resolution: no KDF
   change now; a structural guard instead** (§6.G) so a human-passphrase
   path can never ship without Argon2id. XChaCha20 (192-bit nonce) recorded
   as an OHBK v3 candidate, not this round (wire-format change, low risk at
   household volumes).

## 2. New capability map (what lives where)

**`sanctuary_auth_core` — NO changes.** The crypto core stays frozen this
round (stability is a feature). Everything below is layered on top.

**`sanctuary_backup_ui` — all five new mechanisms:**

- **A. BackupVault** — an app-controlled store of stamped `.ohbk` snapshots
  (`<appId>-backup-<ISO8601-UTC-stamp>.ohbk`) with a keep-N retention policy.
  Storage behind a `VaultStore` seam: native = app documents dir via a
  conditional-import trio; web = OPFS (falling back to IndexedDB), riding the
  fleet's existing `navigator.storage.persist()` precedent. Entries can be
  **pinned** (never auto-pruned). Pruning removes oldest unpinned beyond N.
- **B. Mandatory pre-restore snapshot** — `BackupFlow.runRestore` takes a
  vault snapshot of CURRENT data before any restore executes and **refuses
  to proceed if the snapshot fails** (fail-closed; this is the "requires"
  in the user's ask). The snapshot is labeled `pre-restore` and pinned for
  the session so pruning can't eat the rollback while you're mid-mistake.
- **C. Verify + read-back** — `BackupFlow.verify(blob)`: decrypt → envelope
  checks → serializer dry-run parse → row counts; NEVER writes. Every export
  automatically verifies its own output by read-back before reporting
  success ("Backed up and verified — N items").
- **D. Preview-before-restore** — before the confirm dialog: backup's app,
  schema version, created-at stamp, **age** ("this backup is 12 days old"),
  and per-table row counts vs current counts. Copy stays calm; age is
  information, not guilt.
- **E. Plaintext export** — one shared "Export as plain JSON (unencrypted)"
  action that emits exactly `serializer.dumpAll()` bytes with honest
  labeling. **Decision on the user's open question: it lives in the shared
  package** — the serializer seam already produces canonical JSON, so this
  is one button implemented once; apps with richer bespoke exports
  (Sundial/Bulwark/Reckon/StillLife) keep them. **Plaintext IMPORT stays
  out of the shared package** — unauthenticated restore is a tamper vector;
  apps that deliberately ship it (StillLife, Sundial) own that decision.
- **F. BackupEnvelope helper** (altitude fix): `BackupEnvelope.wrap/unwrap
  (appId, schemaVersion, createdAt, payload)` so 9 hand-rolled envelope
  implementations stop drifting; adds the standardized `createdAt` stamp
  that preview/staleness needs. Serializer interface gains
  `BackupManifest describe(Uint8List plaintext)` with a default
  implementation via the helper.

**Apps (9, mechanical adoption wave):** bump the package; migrate serializer
to `BackupEnvelope`; wire vault config (N, scope); add the vault management
UI entry ("Previous backups" list → preview / restore / pin / delete).

## 3. Retention policy (defaults; per-app configurable)

- Keep-N = **10** unpinned snapshots (Actual-Budget-scale, KB–MB payloads).
- Snapshot triggers: (1) before every restore — mandatory; (2) a copy of
  every manual export; (3) silent freshness snapshot on app open if the
  newest snapshot is >7 days old (no nag, no badge — it just happens).
- **StillLife exception:** metadata-scope snapshots by default (photos are
  MBs–GBs); a pre-restore snapshot includes photos ONLY when the incoming
  restore is a photos-included `.ohbkz` (rollback must cover what the
  restore will overwrite); photo-ful keep-N = 2.
- 3-2-1 nudge: the export success copy keeps one honest sentence
  ("keep a copy somewhere off this device") — copy, not a feature.

## 4. TDD plan (RED list — each is a failing test written first)

**Vault/retention:** prune-to-N keeps newest + all pinned; stamps are UTC,
sortable, collision-safe (two snapshots same second); web store survives a
simulated eviction check (persisted() precedent); vault list ordering.
**Mandatory snapshot:** restore with a failing VaultStore → RestoreOutcome
new value `snapshotFailed`, DB untouched (provable via row hash before/after);
snapshot content equals current `dumpAll()`; pre-restore snapshot is pinned.
**Verify:** truncated blob, tampered byte, wrong AAD context, future schema,
wrong app — each yields its specific outcome and never writes; export
read-back failure surfaces as export failure, not silent success.
**Preview:** manifest counts match a seeded DB; age string derives from
envelope `createdAt`, not file mtime; preview never mutates.
**Plaintext export:** bytes identical to `dumpAll()`; filename + share copy
carry "unencrypted"; action absent when serializer throws-by-default.
**Envelope helper:** wrap/unwrap round-trip; rejects wrong app + future
schema (ports the 9 apps' existing tests to the shared implementation);
missing `createdAt` tolerated for pre-v2 backups (age shows "unknown").
**Per-app (wave template):** serializer-on-envelope round-trip unchanged;
vault UI renders + 320dp×3.0 sweep incl. OPENED dialogs (per the W4 lesson);
StillLife scoping rules.

## 5. Rollout shape (when green-lit — NOT started)

W1 `sanctuary_backup_ui` v2 (opus, TDD, the whole of §2) → W2 nine-app
adoption fan-out (sonnet ×2 concurrent, mechanical, per-app configs +
StillLife scoping) → W3 adversarial review (retention edge cases, web
persistence, restore-refusal paths, no-dark-pattern copy audit) → W4 ship
(builds, deploys, probes). Core untouched → no filter-repo/publish churn;
the two public package repos get normal pushes.

## 6. Guards & recorded deferrals

- **G. Passphrase guard:** a test in `sanctuary_backup_ui` asserts the only
  key sources are `AuthNotifier`/`CryptoService` mnemonic derivations; any
  future human-passphrase feature MUST add Argon2id (OWASP m=19MiB,t=2,p=1
  floor) — recorded here + in the package README so it can't ship naive.
- Deferred, recorded: XChaCha20 as OHBK v3; GFS (grandfather-father-son)
  tiers beyond keep-N; encrypted vault-at-rest beyond the OS/db layer
  (snapshots are already OHBK-encrypted); Mantle + PunctumTemporis join at
  their own adoption moments.

## 7. Open calls for the user (defaults chosen, flag to change)

1. Keep-N default 10 (per-app override exists) — fine?
2. StillLife photo-snapshot policy per §3 — fine?
3. Plaintext import deliberately NOT shared (per-app choice) — agree?
4. Silent 7-day freshness snapshot — or manual-only?

## 8. Execution decisions (2026-07-16, SGCM pass; user delegated the calls)

**§7 calls resolved as their defaults:** keep-N 10 ✓; plaintext import
stays per-app ✓; silent 7-day freshness ✓; StillLife untouched this wave
(not in the three-app scope), its §3 policy stands for its own adoption.

**Wave scope (user-directed):** Sundial + PunctumTemporis + Lullaby
(mediator's third pick — max proof density: legacy envelope compat, live
PWA for the web vault, shared BackupSettingsSection surface, and the open
restore-adopt defect sits on exactly the flow being rebuilt, so it gets
fixed in-wave). The other six apps adopt in the fleet-standardization
campaign (plan #2), not here.

**Corrections the scout pass forced on §2:**
- **Web VaultStore = OPFS via `dart:js_interop`** (PunctumTemporis'
  in-tree `file_storage_web.dart` pattern), NOT "OPFS falling back to
  IndexedDB": no IndexedDB Dart package exists anywhere in the fleet's
  locks, OPFS is universal on evergreen 2026 browsers, and the vault's
  file-per-blob + index.json model maps 1:1 onto it. Browsers without
  OPFS get an honest fail-closed error on restore — that is the design.
- **BackupEnvelope.unwrap tolerates the legacy fleet shapes** the matrix
  scout catalogued: `app` key optional-when-absent (Lullaby's shipped
  envelopes have none — enforcement keys off the caller), and
  `createdAt` falls back to `exportedAt`/`generatedAt`. `describe()`
  additionally counts a `data` map (StillLife's shape). Wave apps EMIT
  additively (legacy keys kept + `createdAt`/`app` added) so old app
  versions can still restore new backups.
- **Restore is two-phase in the package** (`prepareRestore` →
  preview manifest → `commitRestore`): decrypt-before-snapshot, so
  wrong-phrase attempts never spam snapshots, and the pre-restore
  snapshot is sealed under whichever key opened the backup (device key,
  else the phrase-derived key) — the rollback is recoverable with
  exactly the credentials the user just used.
- **PunctumTemporis adopts the architecture in its own idiom** (its
  "GB-scale video" exclusion rationale was FALSE per its own code — a
  year of clips is "well under a gigabyte" — but it already ships a
  mature, hardened plaintext ZIP backup): shared BackupVault primitives
  hold plaintext metadata.json snapshots (proving the vault is
  crypto-agnostic), the ZIP restore gains the mandatory fail-closed
  pre-restore metadata snapshot + a native clips-dir aside-move
  (rename, keep-1) for real media rollback, create gains mandatory
  verify-by-read-back, and the settings-omitted-from-backup gap is
  fixed. Encrypted PT media (.ohbkz of per-clip OHBK entries, StillLife
  precedent, clips fit the 10 MB cap) is recorded as PT's own future
  adoption moment — a product-identity change, not a retention fix.
