# Experimental Qt 5.15.19 for Android 2.3.3

This SDK targets Android 2.3.3 (API 10), ARMv7 `armeabi-v7a`, using upstream
LLVM/Clang/LLD 21.1.8. It builds shared Qt libraries and the actual QtActivity
Android platform integration. The eight applications use the existing
`tests/` sources; Android adds only a common native entry wrapper and a thin
QtActivity subclass.

## Inputs and tools

Use Docker Desktop with Linux containers, PowerShell 7, Python 3, a JDK with
`javac` and `keytool`, and an Android SDK containing platform 35, Build Tools
36.0.0 and Platform Tools. Set `ANDROID_HOME` or pass `-AndroidSdk`.

Stage the existing Qt 5.15.19, LLVM 21.1.8 and OpenSSL 3.5.7 source archives
in `downloads/`. The additional Android inputs and their SHA256 hashes are
listed in `scripts/fetch/locks/qt5-android-api10-inputs.json`:

```powershell
./scripts/fetch/qt5-android.ps1 -AndroidSdk $env:ANDROID_HOME
```

The old AOSP NDK r7 API 9 native headers/libraries are used with an API 10
compiler target; that archive has no separate native API 10 directory.
The matching Android 2.3.3 ARMv7 kernel is required. The later Google API 10
ARMv7 image is Android 2.3.7 and is not a substitute for this guest.
The emulator preparation script changes only the SDK 2.3.3 ramdisk ABI
properties and leaves the system image unchanged.

## Build and run in order

```powershell
./scripts/build/qt5-android.ps1 -AndroidSdk $env:ANDROID_HOME
./scripts/run/qt5-android-suite.ps1 -AndroidSdk $env:ANDROID_HOME
```

Both commands accept `-OutputDirectory`, defaulting to
`artifacts/qt5-android-gingerbread/`. The build supports `-SdkOnly`.
The Docker recipe contains host tools, runtime, OpenSSL, QtBase, complete Qt
and installed SDK stages. Native source builds run offline against verified
archives with two jobs. Example builds run one application at a time in a
container limited to two CPUs and 3 GiB RAM. Stop the emulator before building.
The suite boots one emulator per APK, first for the mandatory C++23 profile
and then for the eight normal example selftests. Qt-selftest additionally
runs an extended APK built from the same sources: stock Bionic allows only
96 DSOs per process, including the Android framework. The core and extended
profiles partition all 74 Qt check groups without deleting checks, and both
retain all 25 mandatory C++23 checks. The default desktop/full selftest is
unchanged. Widgets and QML also run --gallery-selftest to verify actual
rendering and save PNG artifacts. Android APKs use hidden visibility and
collection of unused code/dependencies; only the native entry point is exported.

Installed SDK contents are exported to `sdk/`, shared libc++ to `native/`,
Android dependency deployments to `deployment/`, and signed APKs to `apk/`.
Guest release/API/ABI, stdout, stderr, exit status and logcat are saved under
`run/<profile>/`. Repeating a run archives the preceding app reports under
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
- Stock Android 2.3.3 emulator rendering uses Qt Quick's software backend.
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
[SDK result report](../results/qt5-android-gingerbread-sdk-llvm21-20261117.md).
