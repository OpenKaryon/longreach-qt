# Qt 4.8.7 Android API 21 x86_64 SDK on LLVM 21.1.8

Validated 2026-11-20 UTC on Android 5.0.2/API 21 x86_64. The selected full
static SDK, all eight shared applications and all twelve emulator cases passed.
The strict C++23 APK passed **25 PASS, 0 FAIL, 0 SKIP**. This is an additional
64-bit profile; the original Android 1.6/armeabi default is retained.
See the [build guide](../targets/qt4-android-lollipop.md).

## SDK and runtime

- SDK image: `longreach-qt4-android-lollipop-x86_64:llvm21`.
- Tested immutable image: `sha256:dca401f16ce4577bb9a8d0303ac690931cf43c8edd938ae01e43400164d24645`.
- Installed prefix: `/opt/qt4-android-x86_64-llvm`; source/object trees are absent.
- Qt archive SHA256: `e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0`.
- Shared upstream LLVM 21.1.8 libc++/ABI/unwinder runtime SHA256:
  `8b03afda56a3f0bc3fc0309b4edb1f5b08ee29b77d68fe5a1a03393d60563dc0`.
- Target: `x86_64-linux-android21`, explicit `-march=x86-64-v2`.
- SDK configure fingerprint: `cf68114b032e35acbe80d8e85282d8a5010c643caa663c91c0e056e4b5b2f03e`.

The installed SDK contains fourteen static modules: Core, Gui, Network, Sql,
Xml, Svg, Script, Declarative, Test, Multimedia, OpenGL, ScriptTools,
XmlPatterns and Qt3Support. All twenty module/plugin/import archives were
checked member by member as ELF64/machine 62. The SVG and minimal plugins and
four Qt Quick 1 labs imports are static. Host qmake reports 4.8.7 and the
installed prefix; moc, rcc, uic, headers, mkspecs and licenses are included.

NDK r27 supplies platform headers, CRT, link stubs and helper sources. Its
compiler and stock C++ runtime are not used. The runtime producer is shared
with the API 21 profiles and does not depend on a Qt 5 or Qt 6 target SDK.
The standalone runtime probe passed the shared 25 checks before the Qt build.
The installed-qmake Core consumer and all final JNI clients select C++23 with
`-fexperimental-library`; Qt sources retain GNU++98.

## Guest results

Canonical run: `sdk-suite-4`. Pinned guest Android 5.0.2/LSY66K,
`x86_64-21_r05.zip`, SHA256
`b652297c0733cced8e9507e5018d78f56b87141c47e4d7ada60f495469f76d49`.
Official Emulator 32.1.11/build 9536276 archive SHA256:
`7720a38136399a93af4a3da57715d69f26d7b86c74d60ea016162e11f1fae439`.
The guest used kernel-ranchu 3.10, Nehalem software CPU emulation, 1 GiB RAM
and SwiftShader GLES, headless with no host input capture.

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

Bootstrap returns 42; strict, Core and ordinary clients return 0. Gallery
validation uses Android instrumentation completion code -1, not a fabricated
native return. Its five checks exercise a real QML first frame, tap/state
changes, pause/resume, gallery navigation and Widgets checkbox/tab input.

The strict gate checks the canonical 25 named behaviors and the classic C
locale. Ordinary SKIPs describe absent Qt-generation APIs or backends:
the API 21 profile has no Android audio-device backend, legacy QGLPixelBuffer
support, SSL or QtWebSockets. The actual GLES2 QGLWidget context, textures,
VBOs, FBO render/readback, shaders, shared contexts and triangle capture passed.
QML's fourteen-page rendering sweep, shader output and mouse navigation passed.

All twelve APKs were independently checked for exactly two x86_64 ELF64/machine
62 libraries and the same separately tested libc++ runtime. The collector
matched SDK IDs, current APK hashes, guest properties, native/instrumentation
results, raw/scoped launch logs and PNG dimensions. Before each case it records
a unique log marker; fatal native/Java errors after that marker still fail.
The shared host adb server stopped responding during one focused attempt.
Subsequent qualification used a task-specific adb socket on localhost:5048;
the global server and unrelated devices were left untouched.

## Compatibility and cache corrections

The Bionic scheduling/group/login guards use their actual API declaration
floors. QtScript selects compiler atomics and its Qt threading backend while
retaining Android OS identity. The existing static-animation, tagged-frame
and XmlPatterns color-mask patches are reused. Qt3Support is enabled for this
QPA profile, with API 21 public DNS properties replacing private resolver state.

The minimal backend implements real EGL/GLES2 pbuffer contexts for offscreen
QtOpenGL clients; it does not claim native Android onscreen GL windows.
Widgets and Qt Quick 1 keep the existing raster/Canvas bridge and shared
application sources. No Android-only application source copies were added.

Visual inspection caught a font-selection defect that the previous numerical
checks missed: the basic font backend chose AndroidClock, which has no letter
A. The new common `font/default-ascii-glyphs` check reproduced that failure.
Generic font fallback now selects Roboto, Noto Serif and Droid Sans Mono.
The same check and the gallery captures then passed with legible labels.

Shared MM/GL/QML report paths now use app-private storage on Android while
retaining desktop locations. QML frame capture waits up to two seconds for
actual varied page pixels after software-GL surface initialization; its pixel
threshold and permanently-blank-frame failure remain unchanged.

Qt 4 Make does not track changed feature defines. The producer fingerprints
configure arguments/compiler wrappers and invalidates affected target
module/plugin objects only on configuration changes. Installed qconfig
metadata is refreshed. A necessary feature-flag correction rebuilt affected
objects once; subsequent identical runs reused them. The font correction
compiled one plugin source in ten seconds. The final same-configuration repeat
performed no C/C++ target compilation or configure invocation.

Copied client caches can have output timestamps newer than replacement SDK
archives. Clients now fingerprint the actual archive manifest and relink on
changes while retaining compilation objects. This was verified with zero
client object compilations during the font-plugin relink.

## Focused regressions and reproducibility

The public default Docker tools stage also built from the historical Docker
directory context. The public SDK Dockerfile passed BuildKit static checks
without warnings; its SDK stage was not executed again for this check.
The native SDK producer and final image packaging ran separately using
retained source/object caches; the full cold Docker SDK build
was not repeated for APK/client corrections.

The phase-routing fixture passed: only explicit SDK mode builds Qt, examples
use a validated immutable image, package/test stay isolated, and stale SDK IDs
or native hashes fail before packaging. PowerShell/Python syntax and shared
API 21 log-boundary fixtures passed. The two changed common selftest
translation units compiled against the ready Qt 6 ARM64 SDK without rebuilding it.

The shared Java loader, completion file and PNG capture compiled against the
pinned Android 1.6 jar. Saved API 4 strict and Quick native libraries were
repackaged without an SDK rebuild from the matching saved suite artifacts
(Quick native SHA256 `5fc8f12eb7a313aff16d11c91a5c2e921eb2e4c7522bdd4fabb7b308bca11ee2`);
Android 1.6 strict 25/25 and all five gallery input/lifecycle checks passed sequentially in the original guest.

Known limits remain: QtActivity/native widget integration is absent from this
Qt 4 bridge; WebKit, Phonon, OpenSSL, D-Bus and ICU are disabled. Audio
playback/capture and native onscreen GL windows are not qualified. No claim is
made for every newer Android version, device GPU or writing system.

## Artifact identities

Local raw evidence is under
`artifacts/qt4-android-lollipop-x86_64/`: `sdk-reports/`, `probe/`,
`cxx23-probe-1/`, `core-suite-2/`, `sdk-suite-4/`, final architecture/results
JSON and `api4-wrapper-regression/`. Build/repeat and regression logs remain
under `build/qt4-android-x86_64/`. Previous APKs are preserved by hash.

| APK profile | SHA256 |
| --- | --- |
| bootstrap | `620a30938f47b1bc1fb9f32dfab563a2531b5cc645a82de5a8a75e928319531b` |
| strict | `f79606501a9f6d9cd8626dc08b78c3026564592f35b18260c0fe213a6f01f496` |
| core | `9689f1fb0b78badd29b76a9016b61d782604eab9a4d8016b757638f0fcf9e07c` |
| selftest | `916a69711fc9e3882cb5a3532ba61c3036c2a2d35549dfc5e21b18d05512aa96` |
| widgets | `66b5531cce5760c0aee57377574ccafea30a9948afcded1a8949aa17d1f4ed46` |
| graphics | `68a191d4b3d920dd219f9fe859b50e4f6dbdda7646a5b1eed5d6231a6307b4b5` |
| painting | `0963a3124cae2322a68f991054d25aa47edf61af58e3c38f1247de3c37c2488f` |
| multimedia | `932e4a757bac3c53f61ae912e433a93d500c2857f28001f8f5f247c94c24756f` |
| gl | `3dd0cbe047b7d91ff951e0e82822e2f61a0b175e3b1f43ee6382844220bc94f1` |
| qml | `75a69e2a30626121e0e771bbe648b287daeb2ebc87ef027143fb7144bc834cf9` |
| network | `dde62e22284c778aec935bab9b9e0c79ab11c3889c38796dd4333cce0a581f31` |
| quick | `6c6fce668c29ac37aa472c10dd95102c84b53251810954848b6af8fbb67f41aa` |

Gallery frame identities:

- `sdk-suite-4\quick\files\qml-gallery.png`, 800×407, SHA256 `622808c37926591224e1a34472f33f4c001470b3feee4df5c8b8411092a72280`.
- `sdk-suite-4\quick\files\widgets-gallery.png`, 800×407, SHA256 `770a5f5e60e17ca5efd0a8accf8bfad97b6dd5d18b08434debcedc2fc09d6e03`.

Native builds used two jobs, two CPUs and a 3 GiB container limit. Every build
and emulator ran sequentially. No local security test suites, push or new Git
tag were invoked.
