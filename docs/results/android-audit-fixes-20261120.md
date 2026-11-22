# Android audit corrections and consumer validation — 2026-11-20

This follow-up covers five selected audit blocks: compiler inputs, result and
APK integrity, license metadata, QtActivity compatibility and documentation.
Remaining ABI builds stayed paused. Builds and guests ran sequentially. No
local security suites, push or release tags were part of this work.

## Build scope and compiler evidence

The shared Android tools image now builds upstream Clang/LLD 21.1.8 from the
SHA256-pinned source archive, using the digest-pinned Ubuntu 22.04 base and
dated apt snapshot. X86, ARM and AArch64 backends are included, with resource
headers and the llvm-readelf alias. The compiler used two jobs and one link job.

The actual source compiler build passed. Version/resource checks and C++23 ELF
object generation passed for ARMv5/API4, ARMv7/API10, AArch64/API21, i686/API21
and x86_64/API21. These object checks do not qualify runtime on pending ABIs.

The cached repeat reused every compiler build stage. RootFS layers and image
configuration matched; renewed BuildKit attestations changed the containerd
image index. The stable compiler content manifest was
`sha256:b84c1607f5e969efc060d04d503641181d9d27c12bf693edb11cd10225001a80`.

Consumer tests below reused existing native Qt SDKs and C++ runtimes. Local
derived images added the source-built host compiler; Qt5 images also received
the Java-only repair. Applications/APKs were refreshed through the public
examples/package entry points. Native Qt was not rebuilt, so these runs do
not claim a complete native SDK rebuild from the revised producer.
Checksums confirmed unchanged native ELF/archive files and C++ runtime:
243 files for Qt5/API10, 245 for Qt5/API21 and 318 for Qt6/API21.

| Consumer | Inspected SDK image | Native SDK origin |
| --- | --- | --- |
| API10 | `sha256:66b3cab917529fc7db955a0d2183586a7ea97998bc5c1e144a79b84f2b477b5d` | `sha256:86cc0185e00ea316eff98f8e5ffe7acc2f1eaae5e346f2fa51dde25bdc74ba8b` |
| API21 Qt5 | `sha256:72c93f0bbf42f4a087231934405357d10a3e97e48b7027ff9205ba5ad853f804` | `sha256:c030f963961b806d69a9ab695210608da21db99632e2a66e4ea8658687a6377c` |
| API21 Qt6 | `sha256:27a372dcbf568244c4d50165767a82163ae8a9cfb959130f0902b02f9bc06231` | `sha256:8d1d5b19afb975c739994a0ffcf36a688e6ccf8a4fd2312bce4e828ceb40944b` |

API10's cache image `86cc0185...` retained application objects from the first
consumer pass; its native SDK originated at `baa66f218c6c3e3a6121294de3eab10e87b0069cfcc09960329e9a969827ce5c`.

## Integrity and ordinary tooling checks

Examples begin by invalidating completion and recording an in-progress
generation. Finish requires every deployment, consistent SDK/ABI and an
unchanged application source snapshot. Packaging verifies all deployment,
Java/JAR and runtime bytes, then binds the complete APK set to that generation.
Test entry points and collectors validate APK provenance before starting a guest.

The failed-first-application integration fixture left old APK files available
for inspection but rejected mixed/incomplete packaging. Nine ordinary artifact
unit tests, seventeen tooling unit tests and the Qt4/5/6 phase fixtures passed.

The actual smoke-runner was compiled against ready Linux Qt4, Qt5 and Qt6 SDKs.
Each rejected missing, malformed, multiple, failed and zero-check summaries,
and accepted a valid summary and a complete eight-child report. The child
reports were controlled fixtures, not new desktop GUI qualification runs.

## QtActivity and Java

Simply restoring upstream ActionMode/Fragment callbacks exposed an API10
Dalvik reflection failure before native main. That failed run is retained as
`qt5-android-gingerbread-audit-20261120/audit-suite-1`.

Patch `27-api10-activity-reflection.patch` preserves those modern callbacks and
adds the ten-method API1-type-only QtActivityLegacy interface. On API10, the
delegate reflects legacy super calls through the interface and registration
filters against framework Activity/Service methods. API11+ uses the upstream
reflection path. The source-list change ensures normal QtAndroid.jar builds
include the interface. The patch fixture yielded the exact tested Java sources.

The shared APK Activity verified the API10 interface and, on API21, all eight
retained modern callback signatures. Both core and extended C++23 profiles
reached native code and passed 25/0/0 on each Qt5 guest.

## Installed-APK results

All rows require native result zero. C++23 additionally requires exactly
25 PASS, 0 FAIL, 0 SKIP. Ordinary device/module SKIPs remain explicit.

### Qt5 Android2.3.3/API10 armeabi-v7a

Run: `artifacts/qt5-android-gingerbread-audit-20261120/audit-suite-2`.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 209 | 0 | 63 |
| widgets-gallery | 90 | 0 | 5 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 38 | 0 | 8 |
| quick-qml-gallery | 24 | 0 | 14 |
| network-gui | 7 | 0 | 0 |
| strict-cxx23-extended | 25 | 0 | 0 |
| qt-selftest-extended | 106 | 0 | 4 |
| widgets-gallery-render | 16 | 0 | 0 |
| quick-qml-gallery-render | 3 | 0 | 0 |

### Qt5 Android5.0.2/API21 x86_64

Run: `audit-suite-3`.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 209 | 0 | 63 |
| widgets-gallery | 90 | 0 | 5 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 53 | 0 | 6 |
| quick-qml-gallery | 25 | 0 | 13 |
| network-gui | 7 | 0 | 0 |
| strict-cxx23-extended | 25 | 0 | 0 |
| qt-selftest-extended | 106 | 0 | 4 |
| widgets-gui | 16 | 0 | 0 |
| qml-gui | 3 | 0 | 0 |

### Qt6 Android5.0.2/API21 x86_64

Run: `audit-suite-1`.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 293 | 0 | 43 |
| widgets-gallery | 91 | 0 | 4 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 58 | 0 | 1 |
| quick-qml-gallery | 35 | 0 | 5 |
| network-gui | 7 | 0 | 0 |
| widgets-gui | 16 | 0 | 0 |
| qml-gui | 3 | 0 | 0 |

## Evidence limits and retained failures

The first API21 Qt5 full attempt (`audit-suite-2`) stopped after Graphics
Gallery returned zero: Android RenderThread then reported EGL_BAD_CONTEXT
and a fatal SIGILL. The runner correctly rejected the case. The identical
APK passed an isolated fresh-guest check (32/0/0), then the complete thirteen
cases passed in `audit-suite-3`. No SDK/APK rebuild or relaxed fatal gate
separated those checks. This records observed emulator renderer instability;
it does not claim that its cause was fixed or that repeated cleanup is proven stable.

API10 QML emitted enough old-emulator EGL diagnostics to roll early Java
markers out of logcat. Its zero result and rendered PNG were preserved; both
strict profiles retained their Java markers. Extended API10 startup also
retains caught optional QtPositioning reflection warnings involving absent
GnssStatus types. Native checks completed, but GPS/GNSS hardware is not qualified.

Widgets and QML PNGs were inspected on both Qt5 guests and the Qt6 guest. Passing these examples
does not establish absent camera, audio-input, Bluetooth, NFC or billing hardware.

License headers follow the existing Qt4/Qt5/Qt6 file classifications; the new
Java patch combines the BSD bindings and Qt library license expressions.
The three license matrices parsed successfully. Original result reports now
distinguish prototype/full runs from producer-only and focused follow-ups.

Raw compiler, fixture and Java preparation logs remain under the ignored
`build/review-claude-20261120/` directory. Exact APKs, generation manifests,
source snapshots, scoped/raw logs and images remain under the corresponding
ignored `artifacts/*-audit-20261120/` roots. API21 collectors matched every
case to its current APK SHA256, launch marker and native result.


## Scope after the additional ABI integration

The ARMv7 API10 consumer run above used its recorded older native runtime.
Later Gingerbread runtime-header changes introduced with the x86 profile are
part of the current producer recipe, not retroactive evidence for that ARMv7
image. A runtime built with those changed inputs requires a new ARMv7 strict
25/25 qualification; this historical report does not claim it. Likewise the
older Qt5 ARM64 SDK retains its recorded 56-patch Java stack.

The next [audit follow-up](android-audit-fixes-20261121.md) distinguishes the
focused x86 futex repair from untouched native SDKs and documents cache,
packaging and coverage corrections.
