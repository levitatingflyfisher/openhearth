# home_widget Spike Results

> **Historical spike record, not current state.** The Android widget files it describes exist but are not wired into the app. The iOS widget files were removed in November 2026: nothing built or wrote to them, and their app group, `group.com.porch.app`, named a domain the publisher does not hold. A future iOS widget needs an app group under a domain the publisher holds. Its follow-up list refers to plans that are not in this repo. See [HONEST-STATUS.md](../HONEST-STATUS.md) for what is built.

## What Was Created

### iOS (WidgetKit)
- `app/ios/PorchWidget/PorchWidget.swift` — WidgetKit timeline provider + entry view displaying "Porch" text
- `app/ios/PorchWidget/Info.plist` — extension Info.plist
- `app/ios/PorchWidget/PorchWidget.entitlements` — App Groups entitlement (`group.com.porch.app`)

The iOS widget reads from the shared `UserDefaults` App Group written by `home_widget`, renders available friend count and names. Two sizes: small (count only) and medium (names list).

### Android (AppWidget)
- `app/android/app/src/main/kotlin/com/porch/app/PorchWidgetProvider.kt` — AppWidgetProvider reading SharedPreferences written by `home_widget`
- `app/android/app/src/main/res/xml/porch_widget_info.xml` — widget metadata (4×2 min size)
- `app/android/app/src/main/res/layout/porch_widget_layout.xml` — widget layout XML
- `AndroidManifest.xml` — updated with receiver entry

## Build Results

**Android: BLOCKED — environment issue**

```
java.lang.IllegalArgumentException: 25.0.1
  at org.jetbrains.kotlin.com.intellij.util.lang.JavaVersion.parse(JavaVersion.java:307)
  at org.jetbrains.kotlin.com.intellij.util.lang.JavaVersion.current(JavaVersion.java:176)
```

**Root cause:** Gradle 8.14 bundles Kotlin DSL using Kotlin 2.0.21 (released before Java 25). Java 25's `java.version` string (`"25.0.1"`) is not parseable by Kotlin 2.0.21's `JavaVersion` utility. This is a known compatibility gap — Kotlin 2.2.0+ added Java 25 support.

**System has:** Java 25.0.1 only (no Java 21 installed)

**iOS: Not verified** — iOS build requires macOS + Xcode. Files were created manually based on home_widget docs and will be tested on macOS.

## Required Fix Before Continuing

One of:

1. **Install Java 21** (recommended):
   ```bash
   sudo dnf install java-21-openjdk-devel
   export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
   ```

2. **Upgrade Gradle** to a version bundling Kotlin 2.2.0+ (supports Java 25):
   In `app/android/gradle/wrapper/gradle-wrapper.properties`, change:
   ```
   distributionUrl=https\://services.gradle.org/distributions/gradle-9.0-all.zip
   ```
   (once Gradle 9.0 is released, or whichever version first bundles Kotlin 2.2.x)

3. **Set JAVA_HOME to Java 21** per-project via `.env` if Java 21 is installed elsewhere.

## home_widget Viability Assessment

The `home_widget` package itself is **viable**:
- The iOS WidgetKit extension integration pattern is well-established
- The Android AppWidget integration is standard
- The data bridge (SharedPreferences on Android, App Groups UserDefaults on iOS) is what `home_widget` provides — this is the correct approach
- No concerns about the package itself; the blocker is purely environmental

## Follow-up Required

- [ ] Install Java 21 or upgrade Gradle before Task 11 (Flutter project full setup)
- [ ] Add this fix to `docs/superpowers/plans/2026-03-24-porch-v1.md` Task 11 prerequisites
- [ ] iOS: verify WidgetKit extension builds on macOS when available
- [ ] Task 21: call `HomeWidget.setAppGroupId("group.com.porch.app")` in Flutter init before any `saveWidgetData` call — iOS silently returns error `-7` if this is omitted, with no runtime crash
- [ ] Task 21: confirm `group.com.porch.app` in `PorchWidget.entitlements` matches main app's entitlements (mismatch causes silent UserDefaults nil reads)
