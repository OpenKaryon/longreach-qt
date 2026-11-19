# Qt 6 Android API 21 ARMv7 with LLVM 21.1.8

Original SDK/emulator verification: 2026-11-18 UTC. Repository producer
integration and build verification: 2026-11-19 UTC. This report records a source backport; no binary SDK release
is included.

## Final result

Qt **6.8.5** and its supported Android modules built with upstream LLVM
**21.1.8** for **armeabi-v7a / API21**. The standalone C++23 APK passed before
QtCore was built; QtCore then launched successfully, followed by the full SDK.
The final installed-SDK examples passed all **11 required launch profiles**
in `sdk-suite-8`, with the default OpenGL backend and no forced software backend.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 292 | 0 | 43 |
| widgets-gallery | 91 | 0 | 4 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 58 | 0 | 1 |
| quick-qml-gallery | 35 | 0 | 5 |
| network-gui | 7 | 0 | 0 |
| widgets-gui | 16 | 0 | 0 |
| qml-gui | 3 | 0 | 0 |

The strict run reports Clang **21.1.8**, libc++ **210108** and
`__cplusplus=202302`. All **25 required modern-C++ behaviors passed without
FAIL or SKIP**. They include jthread stop/join, stop-token callbacks and
condition-variable cancellation, atomic wait/notify, thread-local destruction,
exception unwinding/RAII, Unicode filesystem round-trip, format/print and
expected monadic error propagation. This verifies the required behavior set,
rather than every facility in the C++23 standard library.

All eight ordinary examples returned zero. Their SKIPs describe removed Qt5
APIs, platform-specific capabilities and explicitly unavailable features:
Script/XmlPatterns and old multimedia controls, Windows/macOS/X11/Wayland
interfaces, DBus/Vulkan, ICU numeric collation, and decode-only image formats.
The ordinary console speech check delegates live voices to multimedia-lab,
whose speech check passed. Qt3D's one SKIP is its removed scene-change API.
The five QML SKIPs are four uncompiled graphics backends and Wayland.

Both formerly failing QML frame probes now **PASS**: the Quick3D render
extension executes a real frame and the scene graph exposes a native OpenGL
texture. DataVisualization graph checks also pass; they were not skipped to
avoid the earlier initialization/shader failures.

The final Widgets montage and Qt Quick Controls image were visually inspected:
both contain the rendered application UI. Evidence lives in
`sdk-suite-8/widgets-gui/files/widgets-gallery-pages.png` and
`sdk-suite-8/qml-gui/files/quick-gallery.png` under the artifact root below.

## Inputs and actual guest

- Qt 6.8.5 source archive SHA256:
  `c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9`.
- LLVM 21.1.8 source archive SHA256:
  `4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142`.
  No llvm-mingw compiler or NDK-provided libc++ is used.
- OpenSSL 3.5.7 archive SHA256:
  `a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8`.
- Android NDK r27, `27.0.12077973`, supplies platform headers, API21 link
  stubs, CRT objects and CPU-feature sources. The original probe read the
  Windows package. The repository producer uses `android-ndk-r27-linux.zip`,
  SHA256 `2f17eb8bcbfdc40201c0b36e9a70826fcd2524ab7a2a235e2c71186c302da1dc`.
  Its platform/CRT/CPU-feature inputs match the original; the compiler and
  libc++ remain upstream LLVM21.1.8. All producer inputs are pinned in
  `scripts/fetch/locks/qt6-android-api21-inputs.json`.
- Official AOSP API21 ARMv7 image revision4:
  `https://dl.google.com/android/repository/sys-img/android/armeabi-v7a-21_r04.zip`.
  SHA256 `4f20bb4abff1fcda7fdde510993d2004b0ca330ae6e7a798ffecc3fbf6d48520`;
  official SDK SHA1 `8c606f81306564b65e41303d2603e4c42ded0d10`.
- Actual guest: **Android 5.0.2**, API **21**, build **LSY66K**, ABI
  **armeabi-v7a**. This verifies the Android5.0/API21 family on 5.0.2;
  a separate Android5.0.0 run was not performed.
- Emulator: SDK Tools24.4.1 `emulator-arm.exe`, Cortex-A8, 1024MiB actual
  RAM and 1024MiB partition, headless, no host keyboard/mouse capture.
  Early 512MiB requests were automatically increased to 1024MiB by the emulator;
  the final command requests the actual size explicitly.
- GLES2 uses the host NVIDIA OpenGL translator with `-gpu on`. The old
  `-gpu off` renderer does not implement GLES2. Direct emulator invocation
  requires its `tools/lib` directory in the child's DLL search path.
- Linux Build Tools36.0.0 archive SHA256:
  `5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b`;
  official SHA1 `b0b6376977657e8ad9b969bacf4093601da2c6fb`.
- API21 platform revision2 used for Java API comparison, SHA256:
  `a76cd7ad3080ac6ce9f037cb935b399a1bad396c0605d4ff42f693695f1dcefe`.

## Runtime and installed SDK

The native target is `armv7a-linux-androideabi21`, ARMv7-A, VFPv3-D16,
softfp ABI, emulated TLS. libc++, libc++abi, libunwind, libc++experimental
and compiler-rt builtins come from LLVM21.1.8. The ABI and unwinder are
combined in one `libc++_shared.so`. libc++abi uses its thread-exit fallback
because the public `__cxa_thread_atexit_impl` entry point starts at API23.

`LLVM_FORCE_SMALLFILE_FOR_ANDROID=TRUE` avoids requiring the API24 large-file
stdio entry points in the 32-bit runtime. Native classic locale behavior
passes; no locale replacement was needed. The existing legacy-Android
`tmpfile` adapter selects app-private TMPDIR, fixing the initial two print-test
failures without changing the required checks.

The full SDK contains **137 Qt module DSOs**, **10 Android JARs** and
**290 ARM32 shared libraries** including plugins, QML modules and the LLVM
runtime. All 290 pass the API21 loader-format/ABI check: SysV hash present,
no native ELF TLS or newer packed relocations, no GNU/host runtime dependency
and no stock NDK libc++ namespace symbols. Both builds record 28 platform/CRT/
CPU-feature inputs, with LLVM21 C++ headers recorded separately. The original
probe has 1,561 effective headers. The Linux NDK producer has the same headers
plus eight case-distinct netfilter headers (1,569 total).

SDK configuration includes OpenGL ES, linked static OpenSSL3.5.7, Android
multimedia/OpenSLES, native WebView, Quick/Quick3D, Charts/DataVisualization/
Graphs, positioning, Bluetooth/NFC, sensors, serial bus, remote objects and
the other enabled Android modules. Vulkan, WebEngine, Wayland, DBus, glib,
ICU and iconv are disabled. Multimedia uses the native Android backend;
FFmpeg is not included. GRPC/Protobuf runtime and QML support are present;
their host generators are not included. QDoc and the Clang-based lupdate
parser are disabled because the copied host profile lacks Clang development
packages; the target compiler remains LLVM21.1.8.

`qmake -query` reports Qt6.8.5, `android-clang` and the expected prefix.
This is a qmake query check; the examples build with CMake. The SDK itself
uses C++17, while all eight shared examples use C++23,
`-fexperimental-library` and `SMOKE_REQUIRE_CXX23=ON`.

## Compatibility changes

The Android sysroot patch uses `1ULL << 32` for the hardware-buffer flag,
matching the corrected NDKr28 literal. Only the internal copy of r27 headers
is changed.

| Qt Android patch | Purpose |
| --- | --- |
| 01 Java API21 | Guard newer process/insets/services/theme/text/color/TextureView APIs and provide API21 alternatives. |
| 02 Audio | Delay API23 device callbacks and expose platform-default logical OpenSLES routes on API21/22. |
| 03 OpenXR | Guard Vulkan/GLES extension names by the corresponding compiled graphics API; retain the XR module. |
| 04 Proxy | Query API21's effective ProxyInfo, including PAC, through its runtime `getProxy()` method; retain the API23+ path. |
| 05 Window lifecycle | Handle normal launcher start before API22 `getReferrer`; guard API26 focus highlighting. |
| 06 Device routing | Use the API21/22 three-argument GATT overload and the default capture-monitor audio route. |
| 07 Media helpers | Avoid post-API21 Java Streams/Map/MediaFormat helpers; guard API26 notification channels. |
| 08 Legacy TTS | Adapt old Pico language selection when native Voice enumeration fails, and reject invalid JNI lists/items. |
| 09 DataVisualization | Initialize and clean up hidden Android Q3D graphs on a persistent pbuffer instead of waiting for a hidden window surface. |
| 10 Shader precision | Keep an existing `highp` macro when adding the GLES precision fallback. |

Legacy TTS exposes one logical default voice per locale actually supported
by the engine, using `isLanguageAvailable` and legacy language selection.
This does not claim multiple native voice variants; working native Voice
enumeration keeps its normal path. The multimedia example's voice check
passes on the installed Pico engine.

The external compiler supplies both `__ANDROID__` and the NDK's standard
`ANDROID` alias. Adding the missing alias intentionally invalidated affected
native objects; the LLVM runtime, OpenSSL, generated resources and host tools
were retained. An earlier metadata-only change preserved all **7,041 native
compile/link commands** exactly (zero changed/added/removed). An unchanged
cached SDK follow-up needed only five deployment-copy actions, with no native
recompilation. Later fixes rebuilt their affected sources and dependent links.

The shared tests now identify Qt6 GLES through `QT_CONFIG(opengles2)` while
retaining Qt5's legacy ES macro, guard unavailable IPC features and require
XCB before using QX11Application. On Android, the two existing QML graphics
probe functions run inside the initialized APK: QProcess cannot relaunch its
native shared library as a desktop executable. The native-texture probe uses
a local event loop on Android. Desktop probes retain their child-process
launch path and application event loop.
No required modern-C++ check was changed or skipped.

All eight applications use the shared `tests/` C++ sources and Android native
entry wrapper. Qt6 adds only a thin QtActivity subclass for app-private paths.
Qt finalization is deferred until callers have added optional modules. Qt's
real generated deployment JSON and `androiddeployqt --aux-mode` stage the
dependencies; the APK packager validates all Qt6 `libs.xml` string resources
and archives a previous APK before repackaging.

## Local workflow and evidence

Artifact root: `artifacts/qt6-android-lollipop-probe/` (Git-ignored).

- `final-results.json`: all eleven final cases, counts, APK SHA256 and evidence
  paths; each hash was matched against the current APK after the run.
- `apk/packages.json` and eight APKs: final package hashes and sizes.
- `qt-6.8.5-android-api21-armeabi-v7a-llvm21.1.8-target-sdk.tar`:
  local Qt-component snapshot (388,616,192 bytes), SHA256
  `5475a0d6be83deb20f3c8371e0b46d64f2533c088bdb33b0b492980a2605bcec`.
  It preserves the target SDK's Linux archive metadata; compiler/runtime and
  host-tool prefixes remain separate in the prepared container. Archive
  metadata is recorded in `target-sdk-archive.json` and a `.sha256` sidecar.
- `sdk-suite-8/`: exact guest properties, per-case stdout/stderr, native result,
  launch/install reports, screenshots and logcat, including cleanup checks.
- `sdk-api21-elf.json`, `sdk-modules.txt`, `sdk-qmake-query.txt`,
  `sdk-compiler-version.txt`, `platform-input-provenance.json` and
  `qt-sdk-config.summary`: installed SDK and toolchain evidence.
- `strict-run/` and `core-run/`: earlier standalone25/0/0 and QtCore launch.
  QtCore passed QString UTF-8, Unicode QFile round-trip, QCoreApplication and
  a QTimer event loop with the real Qt6 Android class-loader/JNI context.
- `gui-widget-run-5/`: early normal launcher/QWidget diagnostic, 1/0/0.
  Earlier failed diagnostic directories are retained; `sdk-suite-8` is the
  authoritative complete final result.

## Repository producer verification — 2026-11-19

The build now lives in `docker/qt6/android/Dockerfile` and
`scripts/build/qt6-android/`, with portable Windows build, packaging and
serial emulator wrappers. It no longer requires the external prototype
workspace or a prepared experimental container. The Docker directory contains
only Dockerfile. See the [target guide](../targets/qt6-android-lollipop.md).

```powershell
./scripts/build/qt6-android.ps1 -Mode sdk -AndroidSdk $env:ANDROID_HOME
./scripts/build/qt6-android.ps1 -Mode examples
./scripts/build/qt6-android.ps1 -Mode package -AndroidSdk $env:ANDROID_HOME
./scripts/run/qt6-android-suite.ps1 -AndroidSdk $env:ANDROID_HOME -RunName sdk-suite-1
```

The original combined producer completed a clean SDK build from the pinned Linux NDK,
LLVM, OpenSSL and Qt inputs, followed by compilation, Qt dependency/QML
deployment, signing and verification of all eight APKs. Native compilation
used two jobs, with a single Qt link pool. Runtime/OpenSSL/Qt stages ran
without network access. The final SDK contains the compiler/runtime,
host tools, target Qt, OpenSSL and Android build inputs. Its image is
`longreach-qt6-android-lollipop:llvm21`.

New build evidence is under `artifacts/qt6-android-lollipop/`:

- `sdk-image-id.txt`, `qt-sdk-config.summary`, `sdk-modules.txt`,
  `sdk-api21-elf.json`, `sdk-qmake-query.txt`, `sdk-compiler-version.txt`
  and `platform-input-provenance.json`: 137 Qt module DSOs, 10 Android JARs,
  all 290 ARM32 libraries passing the API21 loader checks, and qmake6.8.5.
- `deployment/` and `apk/packages.json`: eight compiled/deployed APKs with
  verified hashes. Packaging compiles Java against API35, uses minimum/target
  SDK21 and local development v1 signing.
- `producer-validation.json`: the configuration summary, LLVM21 C++ headers,
  shared C++ runtime and platform/CRT inputs match the original probe. Seven
  application DSOs, including `qt-selftest`, are byte-identical. The QML DSO
  has identical machine code and all other sections except its build ID and
  four resource-data bytes: one embedded RCC modification timestamp changed
  from November18 to November19. No application behavior was changed.

Input hash checks, Python/PowerShell/Bash syntax checks, repeated media
preparation and the portable collector against the existing eleven-case
evidence passed. **No new emulator run was performed for this producer
integration.** The runtime table above remains the original `sdk-suite-8`
evidence; newly packaged APKs are recorded as build/package verification,
not as a second emulator result. No second SDK rebuild was performed.

## Scope and limits

- Verified guest and ABI are Android5.0.2/API21/armeabi-v7a; other Android
  patch releases and ABIs were not run here.
- The eight ordinary API/GUI examples and the required25 C++ behaviors pass;
  this is not exhaustive Qt or standard-library conformance coverage.
- Emulator audio was disabled. Live acoustic output, real camera quality,
  physical Bluetooth/NFC devices, XR hardware and production proxy setups
  were not validated. Numeric ICU collation is absent from this profile.
- The pre-API24 32-bit stdio profile is intentional; files above2GiB were not
  exercised. The standalone qmake application path was not tested.

No security/CVE tests were run for this verification. No binary SDK release
or release tag accompanies this experimental backport.

## Pre-commit review

All ten Android patches applied to the pinned clean Qt6.8.5 archive with
zero fuzz. Their 21 resulting source files match the SDK used in `sdk-suite-8`
byte for byte. The sysroot patch also matches the tested header. Local evidence
is recorded in `review-clean-patches.json`. The ordinary Windows/macOS/Linux
probe path retains its original application event loop; the reusable local
loop is selected only for Android APKs. A focused Android rebuild after that
review change produced a byte-identical native QML library, preserving the
existing APK evidence. The desktop native-texture probe also compiled and
passed with the Linux Qt6 LLVM SDK in C++17 under Xvfb/OpenGL. These checks ran
sequentially, without restarting the emulator or executing security tests.


## Independent command modes — 2026-11-19

The Windows entry point now separates `sdk`, `examples`, `package` and `test`;
its default is `examples` with an existing SDK. The Dockerfile, pinned inputs,
compiler/runtime scripts and C++23 requirements are unchanged. Missing SDK
images fail instead of starting an implicit build. Packaging consumes saved
deployments; tests prepare only guest media, without fetching SDK sources.

The focused `test-qt6-android-modes.ps1` checks passed with recording stubs:
four-phase isolation, existing-image reuse, absent/wrong image rejection,
legacy `-SdkOnly`, SDK/test fetch scopes, eight-app packaging preflight and
runner option forwarding. Changed PowerShell files parsed successfully;
the existing SDK image metadata was inspected read-only. No native build,
APK-tool execution or emulator run was performed for this mode separation.
