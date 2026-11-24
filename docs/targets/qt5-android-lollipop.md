# Experimental Qt 5.15.19 for Android API 21

The [make and build-all interface](../android-build.md) provides SDK and ready-APK
`-examples` targets. The individual PowerShell phases below remain available;
use the Android runners to launch saved APKs.

Emulator test mode requires a Windows 10+ host, PowerShell 7 and Python 3.11+.
The [host ownership and completion contract](android-artifacts.md#host-process-ownership-and-completion-receipts)
applies to new qualification; older runs without those receipts stay historical.

These profiles select `arm64-v8a` or `x86_64` on Android 5/API 21 with upstream
LLVM 21.1.8.
The original ARMv7 [API 10 profile](qt5-android-gingerbread.md) remains the default.
Historical reports for both ABIs record that the standalone probe and both installed-SDK C++23 profiles
passed 25/25 with no SKIP. The full SDK, eight applications and all thirteen
emulator cases passed. See the recorded evidence for
[ARM64](../results/qt5-android-lollipop-arm64-v8a-llvm21-20261119.md) and
[x86_64](../results/qt5-android-lollipop-x86_64-llvm21-20261120.md).

## Build and run

Use Docker Desktop with Linux containers, PowerShell 7, Python 3.11+, JDK 17/21,
Android SDK platform 35, Build Tools 36.0.0 and Platform Tools. Set `ANDROID_HOME`
or pass `-AndroidSdk` to each mode.

```powershell
$abi = 'arm64-v8a' # Or x86_64.
./scripts/build/qt5-android.ps1 -Abi $abi -Mode sdk -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Abi $abi -Mode examples -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Abi $abi -Mode package -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt5-android.ps1 -Abi $abi -Mode test -AndroidSdk $env:ANDROID_HOME -RunName sdk-suite-3
```

The default `examples` mode inspects an existing image, validates its Qt/LLVM,
platform/API and ABI labels and runs its immutable ID. It exports the target SDK
and producer reports, compiles all eight common applications in C++23 and stages
their dependencies. The additional extended selftest APK uses the same sources.
A missing/incompatible image produces an error; it does not trigger an SDK build.
`-SdkOnly` remains an alias for `-Mode sdk`.

`package` checks all nine deployments before replacing APKs and uses only saved
SDK/runtime files and host Android/Java tools. `test` never compiles/packages;
it fetches only guest media and runs one task-owned emulator. Builds and guests
must run sequentially. `-RunName` must identify a fresh run directory.

The SDK image is `longreach-qt5-android-lollipop-arm64-v8a:llvm21`, with prefix
`/opt/qt5-android-arm64-v8a-llvm`. Outputs default to
`artifacts/qt5-android-lollipop-arm64-v8a/`. Native SDK consumers can use qmake
or the prefix's `toolchain.cmake` inside the image. Android applications are
shared libraries loaded through the installed SDK's actual QtActivity.
For x86_64, the corresponding image is
`longreach-qt5-android-lollipop-x86_64:llvm21`, prefix
`/opt/qt5-android-x86_64-llvm`, and output directory
`artifacts/qt5-android-lollipop-x86_64/`.

## Inputs and shared components

The Docker directory contains only `Dockerfile`. It selects a legacy/API 10 or
API 21 runtime stage by ABI. API 21 reuses the LLVM/Bionic producer helpers, platform
input lock and emulator launcher first introduced for Qt 6; it does not require
building or downloading a Qt 6 target SDK. NDK r27 supplies platform headers, CRT,
link stubs and helper sources. Its compiler and stock C++ runtime are not used.
Qt, plugins and applications share one upstream LLVM 21.1.8 libc++/ABI/unwinder.
Qt source builds use C++17; strict example clients select C++23.

Qt 5 source/LLVM/OpenSSL archives are pinned in the Qt 5 Android input lock; API 21
platform and emulator inputs use the shared API 21 lock. SDK and test fetch scopes
remain separate. The compiled Java manifest declares minimum/target API 21, with
API 35 compile declarations and local development v1 signing. Packaging uses
Qt's dependency/QML deployer plus aapt/D8/JDK, without Gradle.

The common API 21 runner retains all thirteen Qt 5 cases: two strict C++23 runs,
eight ordinary examples, the extended ordinary selftest, and Widgets/QML GUI
rendering. Each strict profile must pass 25/25 without SKIP. Ordinary platform
SKIPs remain visible. The result collector checks the guest/API/ABI, native exit 0,
fatal cleanup errors, case completeness, current APK SHA256 and matching SDK /
example image identities. Qt 6 continues to require its original eleven cases.

## Boundaries

ARM64 uses the pinned Android 5.0.2/LSY66K r04 image, Tools 25.2.5 and its
ARM64 kernel 3.10. x86_64 uses the r05 image, Emulator 32.1.11/9536276 and
`kernel-ranchu` 3.10 with Nehalem two-core software CPU emulation and SwiftShader
GLES. Both use the normal Qt Quick GLES backend; no host input capture is used. The old
API 10 suite still uses its original Gingerbread kernel and software QtQuick.
API 21/22's LP64 loader limit on long names is handled by a basename retry for an
existing absolute plugin path of at least 128 encoded bytes. Other loader errors
remain visible. Newer Android API paths remain guarded by the existing patches.

Physical camera, Bluetooth/NFC, sensors, live audio/GPS and production purchases
require device validation. QtWebEngine is excluded. Files above 2 GiB are untested
with this pre-API 24 stdio profile. AndroidExtras native service/Binder/Intent
coverage remains the previously documented gap. Passing these cases does not
claim exhaustive Qt/C++23 conformance or validation on Android 5.0.0.


See [Android artifacts and coverage](android-artifacts.md) for the current
generation, producer-report, timed-wait, launch-classification and process-exit
requirements. Historical runs above do not qualify the changed source or
receipt format; a native refresh is required for changed native observations.

Console selftests retain `android.app.background_running=true` as a historical
suspension workaround; this does not qualify normal Activity pause/resume.
GUI examples retain normal lifecycle handling.

## Focused sound-cache diagnostic

`scripts/run/android-api21-suite.ps1 -QtMajor 5 -SoundCacheTeardown` requires
an explicit ready `-OutputDirectory` and selects its extended selftest APK.
It writes a separate diagnostic with `qualification=false`. ARMv7/x86 use
their API10 APKs on API21; 64-bit profiles use API21 APKs. The four-ABI source
route has recording coverage; real WAV guest behavior remains unqualified.
See the [common diagnostic contract](android-artifacts.md#focused-diagnostics-and-script-layout).
