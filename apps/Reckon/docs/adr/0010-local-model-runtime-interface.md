# ADR-0010: Reckon's own interface to the on-device model, and the move off flutter_gemma

**Status:** Accepted. The interface is built. The move to flutter_edge_ai waits on a
Flutter toolchain move (see "Why the move is not made yet").

## Context

Reckon runs its local model through `flutter_gemma` 0.13.6. pub.dev marks
`flutter_gemma` discontinued: "author has suggested package:flutter_edge_ai as a
replacement". The final `flutter_gemma` release (1.11.4) describes itself as "Moved to
flutter_edge_ai ... new versions ship as flutter_edge_ai". Same author, same verified
publisher (sashadenisov.dev), same repository, MIT.

Until this ADR, `PrivateModeImpl` and the LLM builder named flutter_gemma's
`InferenceModel`, `Message` and `TextResponse` directly, so any runtime change touched
every caller.

## Decision

1. **Reckon owns the interface.** `lib/core/llm/local_model.dart` defines
   `LocalModelRuntime` (loads a file), `LocalModel` (opens chats, closes) and
   `LocalChat` (adds turns, streams the reply, closes). It is pure Dart. `PrivateModeImpl`
   speaks only these types.
2. **One adapter names the package.** `gemma_runtime.dart` maps the interface onto
   flutter_gemma 0.13.6. The init (`gemma_init_*.dart`) is the only other place.
3. **The file is checked before native code sees it.** `local_model_loader.dart`
   refuses a missing file, an empty file, a `.task` that is not a ZIP bundle, and any
   format Reckon does not know, each as a typed `LocalModelLoadError` with a plain
   sentence. A runtime failure becomes `LocalModelStartFailed`, cause kept for the log.
4. **Every chat is closed** in a `finally`. Under flutter_gemma 0.13 the close is a
   no-op (one live session per model, replaced by the next chat). Under flutter_edge_ai
   the chats are detached and hold native memory until closed.
5. **The runtime comes through `localModelRuntimeProvider`,** so tests run the whole
   path from file to answer with a fake runtime and the network switched off.

## Why the move is not made yet

Every real flutter_edge_ai release (1.11.4 to 2.6.0) and every engine package
requires **Dart >= 3.12 and Flutter >= 3.44**. So does flutter_gemma from 1.0.0 on.
Reckon's CI, release workflow and the build machine are on **Flutter 3.38.7 / Dart
3.10.7**. On that toolchain the only resolvable `flutter_edge_ai` is `0.0.1-dev.1`, an
empty name reservation, and `flutter_edge_ai_mediapipe` does not resolve at all. Moving
the toolchain is a fleet decision, not Reckon's.

## What the move will change (from the 2.6.0 source)

- **Packages:** `flutter_edge_ai` (core, registers no engine) plus
  `flutter_edge_ai_mediapipe` for Reckon's `.task` models. Init becomes
  `FlutterEdgeAi.initialize(inferenceEngines: [MediaPipeEngine()])`.
- **Loading:** `FlutterEdgeAi.installModel(modelType:, fileType: ModelFileType.task)
  .fromFile(path).install()`, then `getActiveModel(maxTokens:, preferredBackend:)`.
  `fromFile` still registers the file where it lies; nothing is copied or fetched, and
  core never deletes a `fromFile` model. Reckon keeps downloading the file itself.
- **Running:** `createChat` is deprecated (removed in 3.0); `openChat` returns a
  detached chat that must be closed. Decision 4 covers this.
- **Android:** the MediaPipe engine keeps minSdk 24 and moves `tasks-genai` from
  0.10.33 to 0.10.35 (Apache-2.0). Core drops `localagents-rag`, Guava and
  `litertlm-android`, so the `jniLibs` excludes in `android/app/build.gradle.kts` need a
  fresh look. Core's manifest adds only `uses-native-library` entries, all
  `required="false"`. No plugin adds a permission.
- **Later, LiteRT-LM:** `.litertlm` models (Gemma 4 among them) need
  `flutter_edge_ai_litertlm`, minSdk 30, arm64 only, and its build hook downloads
  prebuilt native libraries from GitHub at build time. That is a question for an F-Droid
  build and is not part of this move. MediaPipe is maintenance-only upstream.

## Consequences

- **Positive:** the runtime move is one adapter file and the init, behind tests that
  already pass.
- **Positive:** a bad model file fails plainly in Dart, never inside native code.
- **Cost:** one more layer of types. Small, and each type has one job.
- **Open:** the toolchain move to Flutter 3.44, which the fleet decides.
