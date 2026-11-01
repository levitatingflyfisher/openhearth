# Passkey (FIDO2) Spike Results

> **Historical spike record, not current state.** Porch does not depend on `passkeys` today; recovery is the 12-word phrase ([ADR-0004](adr/0004-seed-backup-recovery-over-passkeys.md)). Kept for the reasoning behind that ADR.

## Package Used

`passkeys: 2.18.0` (latest as of spike date)
Platform interface: `passkeys_platform_interface: 2.6.0`
Android: `passkeys_android: 2.12.0`
iOS: `passkeys_ios: 2.9.0`

## PRF Extension: NOT SUPPORTED

**Finding:** The `passkeys` package does **not** expose the PRF (`hmac-secret`) extension.

Evidence: `clientExtensionResults` is hardcoded to an empty map in both `RegisterResponseType.toJson()` and `AuthenticateResponseType.toJson()` (in `passkeys_platform_interface-2.6.0/lib/types/`). No extension data can be passed in or returned out.

This means Porch **cannot** use passkeys to derive a Key Encryption Key (KEK) for wrapping the Ed25519 private key. The PRF-based recovery architecture in the original plan is not implementable with this package.

## Architecture Impact for Task 13

The auth design must change:

### Previous plan (PRF-based — NOT FEASIBLE)
```
Passkey PRF output (32 bytes) → KEK → decrypt Ed25519 key from cloud
```

### New plan (Seed Backup Primary)
```
Ed25519 keypair generated at first launch
  └── Stored in flutter_secure_storage (OS keychain/keystore)
  └── Backup: Argon2(PIN, salt) → KEK → secretbox(ed25519_sk) → file in Documents dir

Passkey = optional convenience for app unlock only (prove device possession)
  └── Passkey creates a credential bound to this device
  └── On subsequent launches: passkey auth proves "you are you" before decrypting keychain
  └── Passkey is NOT used for key recovery — only for local auth UX

Recovery (new device):
  1. Install app on new device
  2. Enter PIN → Argon2 → KEK → decrypt seed file (user must have backed it up)
  3. Restored Ed25519 key → login to server → new session token
```

### Implication for Task 15 (Onboarding)
Seed backup must be **strongly encouraged** (not optional) during onboarding — it is the only recovery path. The "Skip for now" option should show a stronger warning:

> "Without this backup, losing your device means losing your Porch account permanently. There is no server-side recovery."

## API Surface (passkeys 2.18.0)

### Register (create passkey)
```dart
import 'package:passkeys/passkeys.dart';

final authenticator = PasskeysAuth();

final response = await authenticator.register(
  RegisterRequest(
    challenge: base64UrlEncode(randomBytes(32)),     // from server
    relyingParty: RelyingParty(
      name: 'Porch',
      id: 'porch.app',                              // must match server origin
    ),
    user: User(
      id: base64UrlEncode(userIdBytes),             // stable user identifier
      name: displayName,
      displayName: displayName,
    ),
    authSelectionCriteria: AuthenticatorSelectionCriteria(
      userVerification: UserVerificationRequirement.preferred,
      residentKey: ResidentKeyRequirement.required, // required for discoverable creds
    ),
    pubKeyCredParams: [
      PubKeyCredParam(type: 'public-key', alg: -7),  // ES256
      PubKeyCredParam(type: 'public-key', alg: -257), // RS256 fallback
    ],
    timeout: 60000,
    attestation: AttestationConveyancePreference.none,
  ),
);
// response: RegisterResponseType { id, rawId, clientDataJSON, attestationObject, transports }
```

### Authenticate (get assertion)
```dart
final response = await authenticator.authenticate(
  AuthenticateRequest(
    challenge: base64UrlEncode(randomBytes(32)),     // from server
    relyingParty: RelyingParty(name: 'Porch', id: 'porch.app'),
    mediation: MediationRequirement.conditional,    // or .required for explicit
    timeout: 60000,
    userVerification: UserVerificationRequirement.preferred,
  ),
);
// response: AuthenticateResponseType { id, rawId, clientDataJSON, authenticatorData, signature, userHandle }
```

## Android Emulator Feasibility

FIDO2 on Android emulators requires:
- API level 28+ ✅ (modern emulators)
- Google Play Services ⚠️ — standard AOSP emulators do NOT include Play Services; requires "Google Play" emulator image
- Biometric hardware — emulators support software fingerprint simulation

**Verdict:** Feasible on Android emulator with a "Google Play" system image. Physical device preferred for reliable testing.

## iOS Feasibility

iOS passkeys work in simulator via Face ID simulation. Requires Xcode 15+ and iOS 16+ simulator.

## Recommended Task 13 Implementation

```
auth/
  seed_backup.dart        # PRIMARY: Argon2(PIN) → KEK → secretbox(ed25519_sk)
  passkey_service.dart    # SECONDARY: passkey create/verify for local auth UX only
  auth_service.dart       # Orchestrates: firstLaunch(), recoverWithSeed(), unlockWithPasskey()
```

**firstLaunch():**
1. `KeyPair.generate()` → store in `flutter_secure_storage`
2. `apiClient.registerPublicKey(kp.publicKey)` → store session token
3. Offer passkey creation (device-bound, for future app unlock)
4. Strongly encourage `SeedBackup.save(pin)` — show consequences of skipping

**unlockWithPasskey()** (subsequent launches after device reboot):
1. Passkey auth → proves device possession
2. Access `flutter_secure_storage` to load keypair
3. If session expired: re-login with challenge/signature

**recoverWithSeed()** (new device):
1. User provides seed file + PIN
2. `SeedBackup.load(pin)` → Ed25519 secret key
3. Store in new device's `flutter_secure_storage`
4. `apiClient.login(kp)` → new session

## Follow-up for Plan

- [ ] Update Task 13 description to reflect new architecture (seed backup primary, passkey for local unlock only)
- [ ] Update Task 15 (onboarding) to make seed backup strongly encouraged, not optional
- [ ] Server does not need to change — it still uses Ed25519 challenge/signature auth
