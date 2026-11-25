# Experimental Qt 5.15.19 for Android API 10

The [make and build-all interface](../android-build.md) provides SDK and ready-APK
`-examples` targets. The individual PowerShell phases below remain available;
use the Android runners to launch saved APKs.

Emulator test mode requires a Windows 10+ host, PowerShell 7 and Python 3.11+.
The [host ownership and completion contract](android-artifacts.md#host-process-ownership-and-completion-receipts)
applies to new qualification; older runs without those receipts stay historical.

This SDK targets Android API 10 with ARMv7 `armeabi-v7a` or `x86`, using
upstream LLVM/Clang/LLD 21.1.8. The ARMv7 guest is Android 2.3.3; the official
x86 revision5 image actually runs Android 2.3.7. It builds shared Qt libraries and the actual QtActivity
Android platform integration. The eight applications use the existing
`tests/` sources; Android adds only a common native entry wrapper and a thin
QtActivity subclass.

## Inputs and tools

Use Docker Desktop with Linux containers, PowerShell 7, Python 3.11+, a JDK with
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
NDKr7 native archive and official x86 image. The stock legacy path runs
headlessly without acceleration using `core2duo`. Supplying an already-built
corrected classic emulator with `-Mode test -Abi x86 -Emulator /absolute/path/to/emulator-x86.exe`
selects the classic arguments, `-disable-hax` and `-cpu qemu32`, for every case.
The affected stock emulator is expected to fail the mandatory COW preflight;
test mode does not build or patch an emulator.
The x86 runtime targets i686/SSSE3 without SSE4 or AVX. Its DWARF unwinder uses
the old Bionic program-header iterator with frame-header caching disabled;
concurrent library unloading during unwinding has not been qualified.
The Docker recipe contains host tools, runtime, OpenSSL, QtBase, complete Qt
and installed SDK stages. Native source builds run offline against verified
archives with two jobs by default (`-ParallelJobs` selects another limit).
Example builds run one application at a time in a
container limited to two CPUs and 3 GiB RAM. Stop the emulator before building.
The suite boots a fresh guest per case. On x86, `atomic-cow` runs first and
must pass before strict C++23 or the normal applications. ARMv7 starts with
strict C++23. Both then run the eight normal example selftests. Qt-selftest additionally
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

## Shared build and result contract

See [Android artifacts and coverage](android-artifacts.md) for generation
receipts, packaging tools/keys, producer report inventories, CPU/ABI checks,
coverage, deadlines, ADB endpoint selection and observed process termination.
Shared host tools use the digest-pinned Ubuntu 22.04 image, dated apt snapshot
and pinned LLVM21.1.8 sources. A changed recipe needs an explicit fresh SDK;
an existing image tag does not establish source freshness.

Android fixtures are grouped under `scripts/tests/android/`; for example,
`test-qt5-android-modes.ps1` checks phase forwarding with recording stubs.
Shared runner implementations are under `scripts/run/android/`.

## Implementation notes and current evidence

The API10 QML gallery selects GIF/JPEG/SVG image plugins (PNG is built into
QtGui) to stay below Bionic's 96-DSO limit. Other APKs retain normal deployer
selection; the SDK's module set and strict C++23 checks are unchanged.
Console selftests retain `android.app.background_running=true`, a workaround
for historical suspension stalls. It disables dispatcher suspension and does
not qualify Activity pause/resume or establish the cause of those stalls.
GUI examples keep normal lifecycle handling.

The x86 futex stub uses a kernel WAIT/WAKE trap with libc error semantics.
Patch28 uses the condition variable's matching clock. Patch29 retains sensor
queues through looper dispatch and stops polling before application teardown;
compass shares that queue ownership. SDK checks reject undefined x86 `futex`
imports and bind the API21 forward-symbol report. Pinned NDKr27 is used only
as API21 export metadata here, not as the API10 compiler/runtime.

The [sensor lifecycle result](../results/qt5-api10-sensor-queue-lifecycle-20261123.md)
records a fresh Qt5 x86 SDK, the 14/14 API10 batch and API21 compatibility runs.
API10 qualifies acceleration and compass teardown; actual compass headings
were measured on API21. That result qualifies its recorded x86 generation.
The [fresh ARMv7 result](../results/qt5-api10-armv7-qualification-20261124.md)
records a new SDK with patches28/29, all-ABI atomics, observed timed waits,
all 13 API10 smoke profiles and the current exit gates, plus one core API10
APK compatibility run on API21. Its three native sensor checks are named SKIPs:
the stock API10 ARM guest cannot open its HAL device and exposes zero sensors
through both C and Java APIs. Native sensor queues on ARM remain unqualified.
These measurements do not qualify other ABIs, Qt majors or a full API21 suite.
The [earlier sound-cache result](../results/qt5-android-gingerbread-x86-sample-cache-fix-20261122.md)
retains its [exit-evidence correction](../results/qt5-android-api10-exit-evidence-20261123.md).

Patch30 binds each speech callback to an engine identity and utterance generation,
checked when the event reaches the Qt thread. Replaced, stopped, paused or
completed utterances cannot change a newer request's state. API10 reports
Speaking after successful dispatch; API15+ retains its onStart/onDone listener.
Dispatch failures report BackendError. Host regressions execute the Java
adapter with recording Android substitutes and the native state methods with
real QtCore delivery and substituted JNI calls; they do not qualify an Android
TTS engine or audible speech. Changed SDK/APK generations need a guest refresh.

## Diagnose an API10 APK on API21

With a complete matching API10 SDK/examples/APK generation:

```powershell
./scripts/run/android-api21-suite.ps1 -QtMajor 5 -Abi x86 -Api10Compatibility -AndroidSdk $env:ANDROID_HOME
```

Use `armeabi-v7a` for the other API10 ABI. `-OutputDirectory` selects a custom
complete generation. Use a fresh `-RunName`; this route runs one core selftest
with its source API10 policy and writes a separate compatibility diagnostic.
It cannot be combined with `-CaseNames` or the WAV mode. See the
[shared diagnostic contract](android-artifacts.md#focused-diagnostics-and-script-layout).

The separate `scripts/run/qt5-android-sound-cache.ps1` driver records twenty
API10 WAV teardown attempts. Its source/recording coverage does not establish
real WAV teardown behavior or fix qualification. It has no Make alias and
requires ready APK/media inputs; no emulator build is performed.
