import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

// porch's recorded fleet posture. Three checks are off on purpose:
//  - C2 backup: porch does not use sanctuary_backup_ui or the OHBK
//    envelope. Its backup is its own Argon2id blob, locked by 6 words
//    Porch picks, holding the identity entropy and the encrypted state
//    (ADR-0004, docs/explanation/build-spec.md), and it has no shared
//    vault. C2
//    would demand the shared package, which porch has no use for today.
//  - C3 budgets: the only artifacts on disk (build/web, the arm64 APK) are
//    from 2026-07-10, before this app took the design package and its
//    fonts. A baseline measured from them would ratchet against a build
//    that no longer exists. Record budgets.json from the next real build.
//  - C9 routes: porch has no go_router (no GoRoute; screens are pushed as
//    MaterialPageRoutes), so C9 finds nothing and would fail as vacuous.
//    test/presentation/screen_doors_test.dart is porch's own version:
//    every *Screen / *Flow is constructed somewhere outside its own file.
void main() => runFleetConformance(const FleetAppConfig(
      appId: 'porch',
      styleTier: StyleTier.tokens,
      // The app talks to a relay over HTTPS and needs nothing else. The
      // merged-manifest surface is unrecorded: the only merged manifest on
      // disk predates the INTERNET fix and share_plus.
      androidPermissions: {'android.permission.INTERNET'},
      // C12: the primaries porch actually renders (lib/presentation/app.dart
      // porchAmberLight / porchAmberDark; theme_test pins them).
      accentColors: [
        FleetAccent.light(0xFF845416, label: 'porchAmberLight'),
        FleetAccent.dark(0xFFFBBA73, label: 'porchAmberDark'),
      ],
      // Swept at 360 dp x 1.3 in
      // test/presentation/primary_action_sweep_test.dart.
      primaryActionScreens: {'HomeScreen', 'OnboardingFlow'},
      checks: {
        // C13: the PWA loads nothing from Google's CDNs. web/flutter_bootstrap.js
        // points CanvasKit and the engine's fallback fonts at this origin.
        FleetCheck.c13WebSelfHosted,
        FleetCheck.c1Style,
        FleetCheck.c4Permissions,
        FleetCheck.c6Harness,
        // Type comes from openhearth_design's package fonts; C7 sweeps lib/
        // for any character they cannot draw.
        FleetCheck.c7Fonts,
        FleetCheck.c8IconButtons,
        // C14: a SnackBar with an action states persist, or Flutter keeps it
        // up until tapped, across screens. (porch lists its checks, so it
        // takes default-set checks by name.)
        FleetCheck.c14SnackBarPersist,
        // C10: no raw exception text on screen. Onboarding's stored error
        // is the recorded false negative; error_states_test pins it.
        FleetCheck.c10RawErrors,
        // C11: a top-bar action carries a name. Home uses glyph-over-word
        // actions and a worded More menu; Settings has OhThemeToggle.
        FleetCheck.c11IconLabels,
        FleetCheck.c12AccentVsError,
        FleetCheck.c5PrimaryScreens,
      },
    ));
