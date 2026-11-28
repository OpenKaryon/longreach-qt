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
The [2026-11-27 qualification snapshot](../results/android-qualification-20261127.md)
records refreshed ARM64/x86_64 SDK/consumer generations: all thirteen cases
pass with 618 PASS, 0 FAIL and 91 named SKIPs per ABI, natural application
exits, two reviewed gallery PNGs and owned host closure. Separate AndroidExtras
diagnostics pass eight checks, sixteen calls/callbacks and two natural service
exits plus parent exit per ABI. Exact producer/client identities remain distinct.

Earlier [ARM64](../results/qt5-android-lollipop-arm64-v8a-llvm21-20261119.md) and
[x86_64](../results/qt5-android-lollipop-x86_64-llvm21-20261120.md) reports retain
their original generations and limits.

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
require device validation. QtWebEngine is excluded. Separate
[API21 libc++ large-file observations](qt6-android-lollipop.md#large-files-on-api21)
cover native stdio/POSIX operations; Qt filesystem API large-file behavior
requires its own validation. The separate AndroidExtras diagnostic covers the
bounded native service/Binder/Intent paths in the current snapshot.
For `QAndroidServiceConnection`, callers must ensure that no service callback
can begin or remain in flight before C++ destruction starts, including the
derived destructor. Keep the receiver alive until callbacks finish; clearing
the native handle in the base destructor does not protect an already running
callback or the derived object. Concurrent callback/destruction and a separate
asynchronous-close implementation are outside this support contract.
Exhaustive AndroidExtras class/API coverage remains unqualified.
Passing these cases does not claim exhaustive Qt/C++23 conformance or validation
on Android 5.0.0.


See [Android artifacts and coverage](android-artifacts.md) for the current
generation, producer-report, timed-wait, launch-classification and process-exit
requirements. Historical runs above do not qualify the changed source or
receipt format; a native refresh is required for changed native observations.

The pinned Tools25 ARM64 guest emits zero magnetic vectors and its console has
no `sensor` command. Such samples cannot establish a compass heading. The
extended selftest still exercises 32 compass lifecycles during a verified native
acceleration stream and records `heading unavailable (zero magnetic vector)`.
Nonzero magnetic input retains the compass-reading requirement. A separate
recorded stock32 frontend control supplies nonzero magnetic input and 32 actual
Qt compass callbacks on the refreshed ARM64 SDK. It does not establish numeric
azimuth/calibration or physical accuracy, and does not change the Tools25 limit.

Console selftests retain `android.app.background_running=true` as a historical
suspension workaround; this does not qualify normal Activity pause/resume.
GUI examples retain normal lifecycle handling. A bounded ARM64 metadata A/B
pair observed real pause/stop/resume, 83 versus zero background ticks and one
queued UI callback after resume with identical native/DEX inputs. This does not
justify removing the workaround or promise arbitrary background behavior.

The shared speech generation guard also covers API21 callbacks. A late
onDone/onError from a replaced utterance and an onStart after stop are ignored;
normal onStart/onDone transitions remain listener-driven. The
[host regression scope](qt5-android-gingerbread.md#implementation-notes-and-current-evidence)
does not establish Android TTS engine or audible-speech qualification.

## Numeric compass diagnostic

The Qt5 Android extended/full selftest accepts `--compass-heading DEG`, where
`DEG` is one of `0`, `45`, `90`, `180`, `270`. Apply and read back the native
emulator inputs before each fresh application launch: acceleration `(0,0,9.81)`
m/s² and magnetic field `(0,20,-40)`, `(-20,20,-40)`, `(-20,0,-40)`, `(0,-20,-40)`
or `(20,0,-40)` microteslas respectively. The diagnostic requires five
consecutive Qt compass callbacks with matching native vector readings,
angular error at most two degrees modulo a turn and finite calibration in
`[0,1]`. It records the raw angles, vectors, counts and timestamps, then stops
all three sensors. Missing native backends/input is a diagnostic failure.

This separate mode does not change the default suite or its historical
results. It needs independently bound SDK/APK/input identities, native return,
natural application exit, final log capture and owned host-tree closure.
Source/build success alone is not numeric guest qualification. The check does
not establish a raw-angle range, physical calibration accuracy or device coverage.

The recorded API21 ARM64 stock32 run reuses SDK `80f28520`/`f25be055` with
fresh `8c214a8` clients/APKs: five directions, 25 measured samples, 20 PASS,
0 FAIL and 0 SKIP. Native return, natural app exit, post-release/final logs and
owned-tree closure were independently rechecked. Raw readings `-180` and
`-90` are retained for expected `180` and `270` degrees. All 25 native compass
timestamps are 0; this result does not establish timestamp/rate conformance.
The first focused runner attempt returned 2 before checks because the multiword
`am` extra was unquoted. Its logs/disks remain failed; the corrected runner
uses the existing [shell argument helper](../../scripts/run/android/android-shell.ps1)
to keep `applicationArguments` as one value, and the same SDK/APK generation.
See the [shared result snapshot](../results/android-qualification-20261127.md).

## Focused sound-cache diagnostic

`scripts/run/android-api21-suite.ps1 -QtMajor 5 -SoundCacheTeardown` requires
an explicit ready `-OutputDirectory` and selects its extended selftest APK.
It writes a separate diagnostic with `qualification=false`. ARMv7/x86 use
their API10 APKs on API21; 64-bit profiles use API21 APKs. The four-ABI source
route has recording coverage; real WAV guest behavior remains unqualified.
See the [common diagnostic contract](android-artifacts.md#focused-diagnostics-and-script-layout).

## Explicit TTS behavior diagnostic

With a complete matching SDK/examples/APK generation carrying patch30 and the
new multimedia client:

```powershell
./scripts/run/android-api21-suite.ps1 -QtMajor 5 -Abi arm64-v8a `
  -SpeechBehavior -OutputDirectory $root -AndroidSdk $env:ANDROID_HOME
```

The API21 route runs only `multimedia-lab --tts-behavior`, validates eight
state observations, and writes `tts-behavior-result.json` inside its unique
run directory. Existing run names are rejected. It cannot be mixed with
`-CaseNames`, WAV mode or API10 forward mode. The collector checks source/SDK/APK
binding, native process exit, fatal cleanup logs, final capture and owned host
tree separately from the TTS transcript; it never publishes a full-suite result.

The [API10 description](qt5-android-gingerbread.md#explicit-android-tts-behavior-diagnostic)
defines the same bounded state, muted synthesis and resume-restart scope. Use
the appropriate ABI and complete artifact root for another target. A successful
diagnostic remains `qualification=false`; it does not establish audible output
or replace the ordinary full suite. Source/fixture tests are not a guest result.


## Dynamic libraries and thread-local state

On API21, keep the library loaded and its `QLibrary`/`QPluginLoader` owner
alive until all threads using its code or `thread_local` objects have finished
their destructors and joined. Do not unload it earlier or rely on
`PreventUnloadHint` for retention. See the shared
[API21 library-lifetime boundary](qt6-android-lollipop.md#dynamic-libraries-and-thread-local-state).


### Positive plugin/TLS owner diagnostic

Configure the Qt5 Android core/full selftest with
`-DSMOKE_ANDROID_PLUGIN_TLS_OWNER=ON`, build `qt-selftest`, and stage it with
the regular Qt5 deployer. The APK additionally contains a small Qt plugin;
it is absent from `libs.xml` and is loaded only by the explicit
`--plugin-tls-owner` mode. Default builds keep this diagnostic disabled.

The mode checks plugin metadata and interface, calls the plugin from one
`std::thread`, joins through its nontrivial TLS destructor, and only then
unloads the retained `QPluginLoader`. It expects return value 43, exactly one
TLS destructor before unload, and deletion of the plugin object at unload.
It does not unload live TLS or call code after unload. Logical loader unload
does not prove removal of the operating system mapping. The fixture's source
alone is not an Android runtime qualification; actual SDK/APK/guest evidence
must be recorded separately.

The separately recorded ARM64/API21 run of source `cc752474` passed all six
checks using the original SDK `80f28520`/`f25be055`. One worker returned 43;
one TLS destructor completed before unload, and the plugin object was deleted
after join. Natural application exit, final logs and owned process closure
were independently verified. See the [qualification snapshot](../results/android-qualification-20261127.md).
Other ABIs, Qt6 and arbitrary plugin concurrency remain separately unqualified.
