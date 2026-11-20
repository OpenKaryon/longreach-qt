# Qt 5.15.19 SDK for Android 2.3.3/API 10 on LLVM 21.1.8

The original full-suite table and image ID describe the original complete
SDK build. The pre-publication follow-up below was a focused Java/selftest
rerun; it does not replace all thirteen original cases with a new full run.

The full shared SDK and the common examples have run on exact Android 2.3.3,
API 10, armeabi-v7a. The native compiler is upstream LLVM 21.1.8 with libc++,
not llvm-mingw. This continues the [initial QtCore/runtime probe](qt5-android-gingerbread-api10-llvm21-20261117.md).

On 2026-11-18 the maintained Docker recipe built the full SDK, all eight
example APKs and the extended selftest APK. All 13 runtime profiles passed
against that clean export, including both strict C++23 runs and actual
Widgets/QML gallery rendering.

## Runtime results

All APKs use the actual QtActivity through the shared SmokeActivity wrapper.
Application sources remain in tests/; Android adds entry-point, deployment
and packaging code, not separate copies of the applications.

| Application/profile | PASS | FAIL | SKIP | Local run directory |
|---|---:|---:|---:|---|
| Strict C++23, core APK | 25 | 0 | 0 | strict-cxx23 |
| qt-selftest, core | 208 | 0 | 63 | qt-selftest |
| widgets-gallery | 90 | 0 | 5 | widgets-gallery |
| graphics-gallery | 32 | 0 | 0 | graphics-gallery |
| painting-lab | 16 | 0 | 0 | painting-lab |
| multimedia-lab | 4 | 0 | 0 | multimedia-lab |
| gl-heavy-gallery | 38 | 0 | 8 | gl-heavy-gallery |
| quick-qml-gallery | 24 | 0 | 14 | quick-qml-gallery |
| network-gui | 7 | 0 | 0 | network-gui |
| Strict C++23, extended APK | 25 | 0 | 0 | strict-cxx23-extended |
| qt-selftest, extended | 106 | 0 | 4 | qt-selftest-extended |
| Widgets gallery rendering | 16 | 0 | 0 | widgets-gallery-render |
| QML gallery rendering | 3 | 0 | 0 | quick-qml-gallery-render |

Every listed run returned zero. Strict runs also passed
scripts/tests/require-modern-cpp.py. Ordinary skips cover unavailable modules,
later Qt generations, hardware/rendering limits and checks exercised by another
example; they do not weaken the strict C++23 requirement.

Evidence is under artifacts/qt5-android-gingerbread/run/<directory>/:
guest.txt asserts release/API/ABI; files/selftest.stdout and selftest.stderr
record checks; selftest-result.txt records return status; native-maps.txt and
logcat.log retain loader/runtime diagnostics. Rendering runs save app-private
PNG files; quick-gallery.png shows the real common Controls 2 gallery.

The core and extended selftest APKs partition the same 74 Qt check groups
(48 and 26) to fit stock Gingerbread's 96-DSO process limit. Both retain all
25 modern C++ checks. The normal desktop/full profile still calls both sets.
QML deployment scans active Qt 5 qrc resources, excluding unrelated Qt 4
resources from dependency discovery. No test groups were removed to fit the
linker limit.

## SDK and toolchain

- Full module installation produced 67 shared Qt libraries, including Quick,
  QuickControls, Qt3D, Quick3D, Multimedia, Location/Mapbox, Sensors, Bluetooth,
  NFC, Purchasing and TextToSpeech. QtWebEngine is excluded; it is not an
  Android Qt module.
- The AOSP NDK r7 API 9 ARM sysroot is used with an API 10 compiler target,
  ARMv7-A, VFPv3-D16, softfp and emulated TLS. That archive has no separate
  native API 10 directory.
- libc++, libc++abi, libunwind, libc++experimental and compiler-rt share one
  libc++_shared.so, preserving exception and TLS state across Qt libraries.
- C/libc++ locales are C/POSIX. Wide-character libc++ APIs and named Unicode
  locales are disabled. Qt's Unicode/QLocale data is independent.
- OpenSSL 3.5.7 is linked statically, without assembly, modules, applications
  or its tests.
- qmake and CMake C++23 consumers compiled; the QtActivity Widgets probe
  returned Qt=5.15.19, C++=202302, clipboard=1, visible=1, expected=42, math=1.
  Focused compilation of changed common QML and speech code also passed C++14.

## Compatibility work

The common Qt 5 patches precede the Android-specific series. The backport
adds missing C/POSIX locale/math/long-double adapters, an inotify fallback,
wait4 and the standard Elf32_auxv_t definition. ARM long double matches double;
the adapters assert that ABI. The existing legacy tmpfile adapter redirects
Bionic's temporary files into APK-private storage, preserving the actual
std::print checks.

The Android integration guards later Java APIs for display/metrics, clipboard,
accessibility, touch, menus and time zones. FEATURE_ACTION_BAR must only be
requested on API 11+: its value collides with the hidden old FEATURE_OPENGL
flag on API 10. QtScript's ARM-mode workaround now recognizes the custom
Android mkspec. Explicit QThread stack sizes use Bionic's existing pthread
API even when the old header omits its POSIX feature macro.

TextToSpeech supports the legacy completion listener and real language/voice
enumeration. Speech controls update after asynchronous initialization.
Purchasing loads safely without Google Billing and uses Qt's generic backend.
Mapbox/Boost, RapidJSON, Quick3D, DataVis and OpenSL compatibility changes retain
the modules in the SDK.

Packaging preserves androiddeployqt's permissions and static_init_classes,
so Bluetooth, Positioning, Multimedia and NFC receive their Android Context
before native checks start.

## Emulator and limits

The guest uses the unchanged Android 2.3.3 SDK system image, a matching AOSP
2.3.3 ARMv7 kernel and a ramdisk modified only for ARMv7 ABI properties. The
later Google API 10 ARMv7 image is Android 2.3.7 and was not used as a substitute.
One headless Cortex-A8 emulator runs at a time, with 256 MiB RAM and no host
keyboard/mouse capture. Containers are stopped before guest runs.

Qt Quick is tested with the software backend. Stock guest GLES does not
establish GLES 2 rendering: Scene2D and DataVis rendering checks report that
limit. QSGEngine requires the OpenGL scene-graph backend; it cannot own the
software adaptation's shared context. Module/value tests do not establish
working real camera, Bluetooth, NFC, GPS, capture or other absent hardware.
The modern accessibility-node bridge requires API 18; in-process Qt
accessibility remains available. No real Google Billing purchases are claimed.

## Reproduction

See the [target guide](../targets/qt5-android-gingerbread.md).
scripts/build/qt5-android.ps1 builds the Docker SDK and then the shared examples
from the installed SDK. scripts/run/qt5-android-suite.ps1 runs strict core,
all eight applications, strict extended, ordinary extended and both rendering
profiles serially. The default clean output is artifacts/qt5-android-gingerbread/.

The clean SDK image is sha256:baa66f218c6c3e3a6121294de3eab10e87b0069cfcc09960329e9a969827ce5c.
It contains 67 Qt libraries. All examples and the extended APK were built in
a separate container with no Qt/LLVM source or Qt build tree; qmake reports
5.15.19 and Clang reports 21.1.8. Local source-free-sdk.txt retains that proof.

The final clean-export runtime suite completed successfully. No security tests
or new release tag were part of this validation.

## Pre-publication review follow-up

Review corrected three execution edges: timed-out QThread workers retain a
valid lifetime without an unsynchronized flag read; repeated runner attempts
archive the previous app reports under previous-<id>/files and reset guest
metadata; hasPermanentMenuKey is guarded by its actual API 14 introduction.
The latter change also protects the untested API 11-13 range; it does not
establish runtime validation of those Android releases.

The revised 51-patch stack applied with only one changed Qt source file.
A second application preserved timestamps. Only QtAndroid.jar and the core
selftest needed rebuilding. Both strict profiles again passed 25/0/0, the
ordinary core passed 208/0/63 twice, and QML rendering passed 3/0/0 in serial
API 10 runs. The previous core report survived the repeated run unchanged.
Evidence is under artifacts/qt5-android-gingerbread-review-20261118/run/.
The image ID above identifies the original complete clean build; these
focused follow-up APKs carry the revised Java jar and selftest.

The changed common QML, speech, scene-graph and thread code compiled in C++14.
All nine tooling regression tests passed. The API inventory now counts Qt 5
AndroidExtras instead of excluding it as an absent platform: 1594/1603
classes are referenced (99.4%, above the unchanged 95% gate). The nine
AndroidExtras classes remain an explicit test-coverage gap, not claimed as
tested by the Activity suite. Qt 4-only artifact-path cleanup was left out.


The separate win-amd64 per-target inventory diagnostic reports 1097/1535
classes (71.5%) both on the unchanged base revision and after these changes.
It is distinct from the overall CI gate and was not treated as an Android
regression or hidden by changing the threshold.

## Separate audit follow-up — 2026-11-20

See the [cross-version audit report](android-audit-fixes-20261120.md) for the
source-compiler validation, result-generation checks and Java compatibility
repair. Its fresh consumer runs have their own SDK/APK identities; they do
not replace this report's original build or runtime provenance.
