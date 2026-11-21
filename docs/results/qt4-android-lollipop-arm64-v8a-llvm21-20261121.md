# Qt 4.8.7 Android API 21 ARM64 SDK on LLVM 21.1.8

Validated 2026-11-21 UTC on Android 5.0.2/API 21, arm64-v8a. All twelve
required cases and all eight shared applications passed. Strict C++23 passed
**25 PASS, 0 FAIL, 0 SKIP**. This completes the planned additional Android ABI
matrix across Qt 4, Qt 5 and Qt 6. Existing ABI defaults are preserved.
See the [shared API 21 build guide](../targets/qt4-android-lollipop.md).

## SDK and provenance

- Image: `longreach-qt4-android-lollipop-arm64-v8a:llvm21`.
- Immutable SDK: `sha256:dc790d4c6241dda2ef7bd33048ea2b0bd3d4e27ecdc7b10996625f24eac050c2`.
- Installed prefix: `/opt/qt4-android-arm64-v8a-llvm`.
- Source-built upstream LLVM 21.1.8 compiler executable SHA256:
  `6c31c191790134904d2b562c4fb82114e3d6540f0f860a253a05bd2d412c94c4`.
- Shared LLVM runtime SHA256: `fa08e29dc1ee5cb12af97b2ca60b25c1b15dd8d198ab7dd648d48395f78e69db`.
- Qt source archive SHA256: `e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0`.
- Effective configure fingerprint: `85416f0d7292304b109549e3431a925af7fd31ece8c4c62cf23fd38756ce9d61`.

The fourteen-module static SDK and all twenty module/plugin/import archives
were checked member by member as ELF64/machine 183. Core, Gui, Network, Sql,
Xml, Svg, Script, Declarative, Test, Multimedia, OpenGL, ScriptTools,
XmlPatterns and Qt3Support are included, together with static minimal/SVG
plugins and four Qt Quick 1 labs imports. Host qmake reports Qt 4.8.7 and
the correct installed prefix; moc/rcc/uic, headers, mkspecs, licenses, producer
reports and the CMake toolchain are installed. Source/object trees and
Qt 5/Qt 6 frameworks are absent from the final image.

The shared API 21 runtime and NDK r27 platform inputs were reused from the
already qualified ARM64 runtime cache. NDK headers, CRT, stubs and helper
sources are used; its compiler and C++ library are not. That runtime was
originally produced with the packaged upstream LLVM 21.1.8 compiler. Qt 4,
all current clients and the installed SDK use the source-built LLVM 21.1.8
compiler identified above. Reusing the runtime does not imply a new
source-built-compiler runtime rebuild. The public Docker recipe supplies the
source-built compiler for a cold runtime build; this qualification ran the
native Qt producer and final image assembly separately from retained caches.
The public Dockerfile passed BuildKit static checks, without another cold
SDK/compiler/runtime rebuild.

## ARM64 port and build checks

QtCore uses Qt 4's portable generic atomic backend. The 4.8.7 JavaScriptCore
source already detects AArch64 and selects the 64-bit JSValue layout, so
no duplicate architecture patch was added. JavaScript JIT is disabled.
Existing Bionic, QtScript, Qt3Support, raster font and EGL compatibility
patches are reused, including the GLES highp macro guard qualified on x86.

Qt sources retain GNU++98; installed-qmake Core and all twelve JNI clients
build as GNU++23 with `-fexperimental-library`. The Core client actually ran
on the guest. A separate CMake/FindQt4 C++23 client built and linked as
AArch64 through the installed toolchain. An identical SDK repeat performed
zero target compilations and zero configure invocations.

The normal phase fixture covers ready-image reuse, wrong ABI rejection,
ARM64 SDK fetch/build routing, all twelve API 21 packages and test-only
subset forwarding. PowerShell/Python syntax and current recipe hash checks
passed. The existing API 4, API 10 x86 and API 21 x86_64 routing was retained.
The runner selects pinned Tools 25.2.5 for ARM64 and keeps Tools 32.1.11 for
x86_64; both use the shared bounded boot supervision and owned-process cleanup.

## Guest results

Canonical run: `sdk-suite-1`. Pinned image `arm64-v8a-21_r04.zip`, Android
5.0.2/LSY66K, SHA256
`6f9f8ab64641ccbea92a02cc85c130a60c3464b87aa9d49952a8d8292f84d073`.
Pinned Windows Tools 25.2.5 SHA256
`da1a0bd9bb358cb52a8fc0a553a060428efe11151e69b9ea7a5cbacb27cf1c7c`.
The guest uses software Cortex-A57 CPU emulation, two guest cores, 1 GiB RAM
and host GLES translation, with no visible window or host input capture.
Native SDK/client builds use two CPUs and 3 GiB RAM; all builds and guests
ran sequentially. The private adb socket is localhost:5048.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| bootstrap | 1 | 0 | 0 |
| strict | 25 | 0 | 0 |
| core | 1 | 0 | 0 |
| selftest | 114 | 0 | 120 |
| widgets | 135 | 0 | 12 |
| graphics | 32 | 0 | 0 |
| painting | 16 | 0 | 0 |
| multimedia | 9 | 0 | 3 |
| gl | 13 | 0 | 1 |
| qml | 30 | 0 | 0 |
| network | 2 | 0 | 2 |
| quick | 5 | 0 | 0 |

The independent collector checked all twelve current SDK/APK identities,
exact runtime bytes, two arm64-v8a ELF64/machine 183 libraries per APK,
guest properties, completion files, raw/scoped launch logs and PNG dimensions.
Bootstrap returns 42; Core, strict and ordinary clients return 0. Gallery
qualification records instrumentation completion -1 and five actual
first-frame, tap, pause/resume, navigation and Widgets input checks.

QML and Widgets PNGs were visually inspected. QML's fourteen-page sweep and
shader effect passed. GLES2 context/texture/VBO/FBO/shader/shared-context and
triangle rendering passed. Ordinary skips describe Qt generation or absent
backends; strict C++23 has no skips. The current SDK's full emulator run
passed on its first attempt. A producer preflight initially found an absent
source-compiler prefix in the older cache, before any Qt build started; the
cache was prepared with the existing source-built host compiler and the full
SDK then built once.

## Limits and artifacts

Qt Quick 1 and Widgets keep the shared raster/Android Canvas bridge rather
than QtActivity/native Android widget windows. EGL pbuffers qualify offscreen
GLES2, not native onscreen GL integration. QtMultimedia value types/pages
work, while Android audio-device/playback support and the legacy
QGLPixelBuffer API are not qualified. WebKit, Phonon, OpenSSL, D-Bus and ICU
are disabled. This does not claim all device GPUs, writing systems or newer
Android versions, nor exhaustive C++23 conformance.

Raw evidence is under `artifacts/qt4-android-lollipop-arm64-v8a/`:
`sdk-reports/`, `sdk-suite-1/`, `final-results.json`,
`apk-architecture-final.json` and `screenshots.json`. Native build, repeat,
CMake, image assembly and phase logs remain in `build/qt4-android-arm64/`.
Local SDK images, emulator media and development signing keys are not release
assets. No local security suites were run and nothing was pushed.

| APK | SHA256 |
| --- | --- |
| bootstrap | `1079ed43ba83ee1cef3d83145a58e37a38a8bcf75faa43307ab777da3286c3c8` |
| strict | `d40afc0d63246f2cc1afe9f6148453194dd7e29565d72a3a4c210b47b7bb17d9` |
| core | `e5c5cab917e7ea40899f1647f775d964777b1ce3dcc3c187aea23c84f782ef81` |
| selftest | `6c54a4a792f4e2cf98ff53274076576e5397b6c846cfed1923be5d1adcabb258` |
| widgets | `455c08adb7149600e40cdb9d3503122cea4d86c59fa2ea2063af52bb7ad51a46` |
| graphics | `97d8d4c1476103cf357c916d4e8b3d973aca0b9a4466a9aaaeb9c8f4f439a6e6` |
| painting | `bdb8326402ee949ed7ddaf3b6407454573c0d51705230d5ce75eaca0df7072bb` |
| multimedia | `faee13ab09ea9e317dfd59252f5b87ef7d1451a82d357ecf6c27ceea0ec88bbe` |
| gl | `d2d71fef0c0d90a5aaae816d0331b2eb7fb50bcb57a68579804ed23802b866c3` |
| qml | `3e4d40ca802a9bbfd8609c2147a9c76cc3a9682ae317ab9b9fcd44d3184c9b6c` |
| network | `d88dbe0a622cdecb4217d968465f1c5a51b1e3568e67b8811a4df6f23f9982ec` |
| quick | `fcafaa3e81c920190505231ee3ebf239224b77e99d438bf20890cdf060ec8b66` |
