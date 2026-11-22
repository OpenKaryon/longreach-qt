# Experimental Qt 5.15.19 for Android API 10

This SDK targets Android API 10 with ARMv7 `armeabi-v7a` or `x86`, using
upstream LLVM/Clang/LLD 21.1.8. The ARMv7 guest is Android 2.3.3; the official
x86 revision5 image actually runs Android 2.3.7. It builds shared Qt libraries and the actual QtActivity
Android platform integration. The eight applications use the existing
`tests/` sources; Android adds only a common native entry wrapper and a thin
QtActivity subclass.

## Inputs and tools

Use Docker Desktop with Linux containers, PowerShell 7, Python 3, a JDK with
`javac` and `keytool`, and an Android SDK containing platform 35, Build Tools
36.0.0 and Platform Tools. Set `ANDROID_HOME` or pass `-AndroidSdk`.

The fetcher stages the pinned Qt 5.15.19, LLVM 21.1.8 and OpenSSL 3.5.7
source archives in `downloads/`. Android inputs and their SHA256 hashes are
listed in `scripts/fetch/locks/qt5-android-api10-inputs.json`:

```powershell
./scripts/fetch/qt5-android.ps1 -AndroidSdk $env:ANDROID_HOME
```

The old AOSP NDK r7 API 9 native headers/libraries are used with an API 10
compiler target; that archive has no separate native API 10 directory.
For ARMv7, the matching Android 2.3.3 kernel is required. The later Google API 10
ARMv7 image is Android 2.3.7 and is not a substitute for this guest.
The emulator preparation script changes only the SDK 2.3.3 ramdisk ABI
properties and leaves the system image unchanged.

## Build and run in order

```powershell
./scripts/build/qt5-android.ps1 -Mode sdk -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Mode examples -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Mode package -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Mode test -AndroidSdk $env:ANDROID_HOME -RunName sdk-suite-1
```

All modes accept `-OutputDirectory`, defaulting to
`artifacts/qt5-android-gingerbread/`. The default mode is `examples`: it requires
a ready matching SDK image and never rebuilds Qt implicitly. `sdk` is the only
mode that builds an SDK image. `-SdkOnly` aliases `-Mode sdk`; local SDK files
are exported during `examples`. `package` uses the saved deployments without
Docker, while `test` uses saved APKs without compilation or packaging.
The examples invocation records and runs the inspected immutable image ID.
`-SdkImage` selects another ready image or the output tag for SDK mode.

The [ARM64/x86_64 API21 profiles](qt5-android-lollipop.md) use the same Dockerfile
and phase entry point with `-Abi arm64-v8a` or `-Abi x86_64`. The original API10
floor remains the default for ARMv7. Select `-Abi x86` for the 32-bit Intel
API10 profile; all four modes support it. Its output is
`artifacts/qt5-android-gingerbread-x86/` and its default image is
`longreach-qt5-android-gingerbread-x86:llvm21`. The fetcher selects the matching
NDKr7 native archive and official x86 image, and the legacy emulator runs
headlessly with software acceleration disabled and the `core2duo` CPU model.
The x86 runtime targets i686/SSSE3 without SSE4 or AVX. Its DWARF unwinder uses
the old Bionic program-header iterator with frame-header caching disabled;
concurrent library unloading during unwinding has not been qualified.
The Docker recipe contains host tools, runtime, OpenSSL, QtBase, complete Qt
and installed SDK stages. Native source builds run offline against verified
archives with two jobs. Example builds run one application at a time in a
container limited to two CPUs and 3 GiB RAM. Stop the emulator before building.
The suite boots one emulator per APK, first for the mandatory C++23 profile
and then for the eight normal example selftests. Qt-selftest additionally
runs an extended APK built from the same sources: stock Bionic allows only
96 DSOs per process, including the Android framework. The core and extended
profiles partition all 74 Qt check groups without deleting checks. Each
compiles only its relevant translation units so unused MOC registrations
do not retain extra libraries in the fixed loader pool. Both
retain all 25 mandatory C++23 checks. The default desktop/full selftest is
unchanged. Widgets and QML also run --gallery-selftest to verify actual
rendering and save PNG artifacts. Android APKs use hidden visibility and
collection of unused code/dependencies; only the native entry point is exported.

Installed SDK contents are exported to `sdk/`, shared libc++ to `native/`,
Android dependency deployments to `deployment/`, and signed APKs to `apk/`.
Guest release/API/ABI, stdout, stderr, exit status and logcat are saved under
`<RunName>/<profile>/` (`run/` for the standalone legacy runner default). Repeating a run archives the preceding app reports under
`previous-<id>/files/` before starting the new guest. A disposable local signing key is generated for example
APKs; API 10 uses v1 signing.

Qt's own `androiddeployqt --aux-mode` selects libraries, plugins and QML
resources. Packaging preserves its permissions and static module-initialization
classes, and uses `aapt`, D8 and the installed JDK without Gradle.
The manifest declares min/target SDK 10 even though Java is compiled against
Android 35 declarations. Native consumers can use the SDK qmake mkspec or
`/opt/qt5-android-armeabi-v7a-llvm/toolchain.cmake` with CMake inside the image.
Android application targets are shared libraries, loaded by QtActivity.

## Platform boundaries

- All native components share one `libc++_shared.so`, including exception and
  emulated TLS state. C++17/20/23 consumers use the same compiler/runtime.
- C/libc++ locale support is C/POSIX. Qt Unicode/QLocale data is separate.
  libc++ wide-character APIs and named Unicode
  locales are not provided by this profile.
- Stock API10 emulator rendering uses Qt Quick's software backend.
  This does not establish GPU rendering or real-device hardware support.
- QtWebEngine is excluded. Google Billing is optional: without its Java
  classes QtPurchasing uses Qt's generic backend, not real purchases.
- Later Android APIs are guarded at runtime. Android's accessibility-node
  bridge requires API 18; in-process Qt accessibility remains available.
- Nine AndroidExtras classes remain a declared API test-coverage gap; the
  Activity suite does not exercise native service/Binder/Intent interfaces.
- Passing ordinary module/value checks does not establish working camera,
  Bluetooth, NFC, sensors, GPS, audio capture or other absent guest hardware.

Build evidence, runtime results and platform limits are recorded in the
[ARMv7 SDK result report](../results/qt5-android-gingerbread-sdk-llvm21-20261117.md)
and [x86 qualification report](../results/qt5-android-gingerbread-x86-llvm21-20261121.md).

## QtActivity across Android versions

The API 10 backport retains the upstream ActionMode and Fragment callbacks
used by newer Android releases. Dalvik on API 10 can load that Activity, but
reflecting its method list also resolves signature types absent from the old
framework. Removing the newer callbacks would break forward compatibility.

`27-api10-activity-reflection.patch` adds a small `QtActivityLegacy` interface
to `QtAndroid.jar` and the Activity template. On API 10, the delegate reflects
its ten legacy `super_*` calls through that interface, whose parameter types
are all available. Callback registration filters against the running
framework's Activity or Service class. API 11 and later retain the upstream
reflection path. The shared APK Activity checks the expected bridge on API 10
and the eight retained callback signatures on API 11 and later; native startup
and example tests remain necessary to verify the full Java/native path.

## Lightweight mode checks

`./scripts/tests/test-qt5-android-modes.ps1` verifies ready-image reuse, ABI
rejection, phase isolation, SDK-only compatibility, all nine deployment inputs
(core plus extended selftest) and test argument forwarding. It uses recording
stubs and temporary fixtures, without building Qt or starting a guest.


## Shared compiler inputs

Android host tools build from the digest-pinned Ubuntu 22.04 image and the
project's dated apt snapshot. Clang/LLD 21.1.8 come from the SHA256-pinned
upstream LLVM source archive, with X86, ARM and AArch64 backends. The host
compiler builds with two jobs and one link job. The shared image is refreshed
through Docker's cache whenever SDK mode is requested; a pre-existing tag is
not a freshness check. Build its Dockerfile with the repository root as context.

These producer inputs describe the current recipe. Earlier result reports
identify the SDKs actually tested; changing the compiler recipe does not
retroactively qualify an older image as a fresh build from the new producer.

## Completed example generations

Examples mode marks the output incomplete before changing any deployment,
Java input or runtime. Only a successful complete build writes
`examples-manifest.json`, recording the selected immutable SDK ID, ABI and
hashes of every packaging input. Packaging checks those files before changing
any APK and writes `apk-manifest.json` only after all APKs finish. Test mode
requires the completed APK generation and verifies its hashes before booting.
Qt 5 includes both core and extended selftest deployments.

A failed rebuild leaves earlier APKs on disk for inspection, but they cannot
be packaged or tested as the new generation. Complete examples mode, then
package mode, before starting the new test run. Existing outputs without
these manifests need that explicit refresh; the scripts do not silently adopt
them or rebuild the SDK. Saved APK test mode needs the manifests and image-ID
files, but it does not require the SDK or deployment directories.

PowerShell 7 is required for the Windows entry points. Ordinary artifact
regressions are `scripts/tests/test_android_artifacts.py` and
`scripts/tests/test-android-generation.ps1`; they need no SDK build or guest.

The [Android audit follow-up](../results/android-audit-fixes-20261120.md)
records the current generation checks and installed-APK consumer validation,
with exact SDK identities and retained failures. Native SDK provenance stays
separate from consumer refreshes.


See [Android artifact generations and coverage](android-artifacts.md) for phase
ownership, packaging receipts, ABI preflight, per-target coverage limits and
the private ADB environment used in local reproduction.


The API10 QML gallery APK limits optional image plugins to GIF/JPEG/SVG from
Qt's deployer selection (PNG is built into QtGui) to leave room below Bionic's 96-DSO loader limit. It does not
package unused desktop image handlers. Other example APKs retain the normal
Qt deployer selection. This packaging limit does not remove modules from the
SDK or relax any QML/strict-C++23 checks.


The console `qt-selftest` APK uses Qt's `android.app.background_running=true`
metadata so its synchronous checks, which have no outer app.exec(), can finish
independently of Activity suspension. GUI examples retain normal lifecycle
handling. The API10 runner also verifies stay-awake for the disposable guest
and retains the power-policy receipt; it does not change host power settings.


The [2026-11-22 x86 sound-cache shutdown qualification](../results/qt5-android-gingerbread-x86-sample-cache-fix-20261122.md)
records the narrow QtMultimedia cleanup correction and all fourteen successful
cases on the unchanged corrected emulator, including COW and both strict C++23
profiles. This result does not qualify the affected stock emulator or another ABI.
