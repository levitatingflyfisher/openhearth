# oh_release_kit

The OpenHearth fleet's release checks, as one command-line tool. Every app
releases the same way: the app's folder is the argument, and each check
exits 1 when it fails.

Pure Dart. No Flutter, no network. It reads files and runs `git`, `tar`,
`sha256sum` and the Android SDK's `aapt2` and `apksigner`.

```bash
cd oh_release_kit
dart pub get
dart run oh_release_kit:release <command> ...
```

Exit 0: every check passed. Exit 1: a check failed. Exit 2: the command
could not run (a missing file, a bad argument, no `aapt2`). A check that
could not run is never read as a pass.

## The commands

### `version <app>`

Version and build number must move together (release rule 1). It checks:

- `pubspec.yaml` has a version with a build number, `1.4.2+31`.
- Every version constant in `lib/` agrees. The rule for finding one: a
  `const appVersion = '1.4.2'`, at top level or `static` in a class, and an
  optional `const appBuildNumber = 31`. Generated files are skipped. An app
  with no constant gets a note, not a failure.
- `CHANGELOG.md` has a heading for the version: `## 1.4.2`, `## [1.4.2]` or
  `## v1.4.2`.
- When `fastlane/metadata/android/<locale>/changelogs/` exists, each locale
  has a changelog for the build. Its name is the build number, or the build
  number plus Flutter's split-per-ABI offset (1000 for armeabi-v7a, 2000 for
  arm64-v8a, 4000 for x86_64), since the store reads the file named for the
  version code it received.

### `shared-versions <app>`

Prints every package the app takes by path from `pubspec.lock`, with its
version, its path and the commit its folder is at. Paste the block into the
release ledger (rule 11). A shared library can change under an app without a
version bump; the commit says what the app was really tested with. A folder
with uncommitted changes is marked so.

### `leakscan <diff> [--private <file>] [--all-lines]`

Scans what a diff adds for anything private before a public push (rule 5).
Only added lines are read, and the path of each new file. Hunk line counts
decide where a hunk ends, so an added line that starts with `++` is still
scanned.

The generic checks are in the code:

- home paths (`/home/<name>/`, `/Users/<name>/` and the Windows user
  folders) and the temporary folder coding agents write under `/tmp`;
- email addresses, except the persona's noreply address, GitHub's SSH
  remote address and the example domains set aside by RFC 2606;
- attribution lines: co-author trailers, the footer a tool adds to say it
  wrote the text, the assistant's web address;
- machine details: memory sizes, core counts, graphics card and processor
  model words, system load figures;
- tokens and private keys (GitHub, API keys, cloud keys, PEM key blocks).

Every private word (people's names, personal domains, family words) comes
only from the `--private` file, which lives outside every public repo. One
regular expression per line, `#` starts a comment line. A pattern that
begins with `(?i)` ignores case. A pattern that does not compile, or a
`--private` file that cannot be read, stops the scan with exit 2. A hit is
reported by the pattern's line number, never by its text, so the report can
be pasted anywhere.

An empty input file is exit 2, not clean: a `git diff` that fails still
leaves an empty file behind.

`--all-lines` treats every line of the file as added. Use it for commit
messages: `git log --format=%B origin/master..master > msgs.txt`.

### `web-check <app> <built web folder> [--base-href /<App>/]`

Checks a built PWA before it is published (step 6):

- `index.html` has a base href, not the unfilled placeholder and not the
  bare root (fleet PWAs are served under `/<App>/`). With `--base-href`, it
  must equal that.
- `manifest.json` is present, parses, and is not Flutter's template.
- `main.dart.js` at gzip level 9 is within `main_dart_js_gz_max_bytes` in the
  app's `budgets.json`. No budget is a note.
- No built file names a CDN or font host (`fonts.googleapis.com`,
  `fonts.gstatic.com`, `unpkg`, `jsdelivr`, `cdnjs`, other Google hosts). The
  engine keeps two default CDN addresses in `main.dart.js`; they pass only
  while the build was made with `--no-web-resources-cdn` and
  `flutter_bootstrap.js` sets `canvasKitBaseUrl` to a relative path and
  `fontFallbackBaseUrl` to `/fonts/flutter-fallback/`, the fleet's shared
  fallback-font mirror.
- CanvasKit is in the build, and `assets/FontManifest.json` lists at least
  one text font, with every listed font file present.

It does not check that the fallback-font mirror itself is complete.

### `apk-check <apk> <app> [--build-tools <dir>]`

Checks a built or downloaded APK against the app's sources (steps 5 and 9).
It runs `aapt2 dump badging` and compares:

- the package name with `applicationId` in `android/app/build.gradle(.kts)`;
- the version code with the pubspec build number (plus the ABI offset for a
  split APK), and any version code the gradle file hard-codes;
- the version name with the pubspec version;
- the size with `apk_arm64_max_bytes` in `budgets.json`, for an arm64 APK.

It prints the sha256 and the signer from `apksigner verify --print-certs`.
A debug-key signature is a note: fleet apps sign with the debug key until a
release key is decided. A failed `apksigner verify` is a failure.

`aapt2` and `apksigner` come from `--build-tools <dir>`, or from the newest
`build-tools/` folder under `ANDROID_HOME` (or `ANDROID_SDK_ROOT`).
`apksigner` needs Java on the `PATH`.

### `export <repo> <commit> <dest>`

Writes `git archive <commit>` into the new folder `<dest>` and prints the
full commit id (rule 2: builds come from a clean export, never a working
tree). It refuses a `<dest>` that exists and a folder under `/tmp`,
`/dev/shm` or `/run`, which are RAM on common Linux systems. A failed export
removes the folder it made.

## The release, step by step

`release` below is `dart run oh_release_kit:release`, run from this folder.
`<app>` is the app's folder, `<notes>` the private release folder.

1. **New release folder.** Copy the newest release folder (scripts, ledger)
   to one for this version.
2. **Version commit.** Bump `pubspec.yaml`, the version constant, the
   CHANGELOG and the fastlane changelog together, then:
   `release version <app>`
3. **Measure; budgets commit if needed.** Build once. A budget that must
   move moves in its own commit with its reason, before the suite.
4. **Full suite on that head.** In the app: `flutter test`.
5. **Recipe build from the same head.**
   `release export <app repo> <commit> <release tree>`, then in the export:
   `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
   and the APK build inside a memory-capped scope, with no Gradle daemon:
   `GRADLE_OPTS="-Dorg.gradle.daemon=false" <capped> flutter build apk --release --split-per-abi --target-platform android-arm64`.
   Then: `release apk-check <export>/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk <app>`
6. **Web check alone.** In the export:
   `<capped> flutter build web --release --no-web-resources-cdn --base-href /<App>/`, then
   `release web-check <app> <export>/build/web --base-href /<App>/`
7. **Leak scan on the diff.**
   `git -C <app repo> diff origin/master..master > <notes>/release.diff`,
   `release leakscan <notes>/release.diff --private <private patterns file>`,
   and the same with `--all-lines` on the commit messages.
8. **Fold, dated the 1st.** Persona author, no attribution lines. The
   maintainers push.
9. **Release, download back, compare.** Download the published APK and run
   `release apk-check <downloaded apk> <app>`. The sha256, version code and
   signer must match step 5.
10. **Web deploy alone,** of the build step 6 checked.
11. **Old release.** Save its record, then delete it. A permanent data
    release is never deleted.
12. **Ledger.** `release shared-versions <app>` into the ledger. Remove the
    release tree.

Each check gates on its own exit code. Never pipe a check into `tail` or
`grep`: the pipe's exit code is the last command's, and a failed check
would pass.

## Working here

```bash
dart test
dart analyze
```

The tests use no network and build nothing. Scratch folders go under
`.dart_tool/kit_test_tmp/` on real disk, never `/tmp`.
