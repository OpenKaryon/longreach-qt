# Qt 4.8.7 Android API 10 x86 SDK on LLVM 21.1.8

Validated 2026-11-21 UTC on the pinned Android 2.3.7/API 10 x86 guest.
All twelve final cases and all eight shared applications passed. The strict
C++23 APK passed **25 PASS, 0 FAIL, 0 SKIP**. The original Android 1.6/armeabi
profile and the existing API 21 x86_64 profile retain their defaults.
See the [build guide](../targets/qt4-android-gingerbread.md).

## SDK and provenance

- Image: `longreach-qt4-android-gingerbread-x86:llvm21`.
- Immutable SDK: `sha256:7dffd68fe1cfde3bced1e990033dea290d5468465b84d7325675ea62fb57a50a`.
- Installed prefix: `/opt/qt4-android-x86-llvm`.
- Upstream source-built LLVM 21.1.8 compiler executable SHA256:
  `6c31c191790134904d2b562c4fb82114e3d6540f0f860a253a05bd2d412c94c4`.
- LLVM libc++/ABI/unwinder/compiler-rt runtime SHA256:
  `c253eff8207403db045f4980c07620f213e7e31427e9f2680c784570eee33489`.
- Qt source archive SHA256: `e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0`.
- Effective configure fingerprint: `7b3bc3b19c472ca78f83b5fdfb9ab649e9c932d04f1888311633b7a01d674294`.

Fourteen static Qt modules and twenty module/plugin/import archives were
validated member by member as ELF32/machine 3. Host qmake reports Qt 4.8.7
and the installed prefix. The final image contains headers, libraries,
moc/rcc/uic/qmake, mkspecs, CMake toolchain, licenses and producer metadata;
Qt source/object trees and the Qt 5 framework are absent.

The recipe reuses the API 10 LLVM runtime producer and pinned NDK r7 API 9
x86 platform inputs. The NDK supplies headers, CRT and link stubs, not the
compiler or C++ library. Qualification reused the already validated platform
runtime from the Qt 5 x86 SDK; Qt 4 itself was built through the public scripts.
Final image assembly copied only the Qt 4 install and shared platform runtime
onto the source-built host tools. No Qt 5 framework enters the Qt 4 recipe or
final SDK. The full cold Docker SDK build was not repeated: the public
Dockerfile passed BuildKit checks, and the native producer and final image
assembly ran separately with retained source/object caches.

Qt sources compile as GNU++98, and all twelve JNI clients use C++23 with
`-fexperimental-library`. The installed-qmake Core client passed in the guest;
a separate CMake/FindQt4 Core client built and linked as ELF32 using the
installed toolchain. Shared application sources and older language modes
were preserved. API 4 phase routing and API 21 image selection passed the
extended normal mode fixture.

## Final emulator results

Canonical run: `sdk-suite-2`. The Google x86 r05 guest reports Android
2.3.7/API 10. Tools 24.4.1 runs it with software Core2Duo CPU emulation,
256 MiB RAM, no visible window and no host input capture. GLES emulation
uses the host translator; the qualified host reported NVIDIA RTX 3090 /
OpenGL 4.6, not a pure software GLES renderer. Builds used two CPUs and
3 GiB RAM; build and guest execution were sequential. A private adb socket
on localhost:5048 left the global server and unrelated devices untouched.

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

The collector independently checked all twelve APK hashes against the SDK
and launch records, exactly two x86 ELF32/machine 3 native libraries per APK,
the exact producer runtime, guest properties, raw/scoped launch logs,
completion files and gallery PNGs. Bootstrap returns 42; ordinary/strict/Core
clients return 0. Gallery evidence uses Android instrumentation completion
code -1 and five actual rendering/input/lifecycle assertions.

Widgets and QML gallery frames were visually inspected with legible labels.
OpenGL context creation, texture upload, VBOs, FBO render/readback, shaders,
context sharing and the rendered triangle passed. QML's fourteen-page sweep,
shader effect and navigation passed. Ordinary skips remain explicit Qt API
or backend limitations; the required C++23 gate has none.

## Corrections and retained failures

The first full run (`sdk-suite-1`) passed strict C++23, Core and five ordinary
cases before GL failed. GPU-off emulation provides only GLES1, while the Qt 4
minimal backend requests GLES2. Enabling GPU emulation first exposed the
legacy backend's missing GLES translator DLL search path (`gles-on-1`).
The runner now adds the pinned tools/lib directory only to its child process
and restores the parent environment.

With GLES available, `gles-on-2` exposed real shader/triangle failures. A small
diagnostic APK captured `Macro highp redefined`: the legacy GLES translator
already defined the qualifier macro and Qt 4 defined it again. The new
Android patch guards Qt's fallback with `!defined(highp)`. Existing desktop
behavior and shader assertions were preserved. Only qglshaderprogram.cpp was
recompiled in the SDK; a subsequent unchanged repeat performed zero target
compilations and zero configure invocations. All final clients/APKs were
rebuilt against the corrected SDK before `sdk-suite-2`.

The diagnostic APK is not counted as Core qualification. Earlier failed
runs and their raw logs remain separate from the final evidence. Strict
C++23 passed both before and after the GL correction.

## Limits and artifacts

Qt Quick 1 and Widgets use the existing raster/Android Canvas bridge rather
than QtActivity/native Android widget windows. Minimal EGL pbuffers qualify
offscreen GLES2, not native onscreen GL. QtMultimedia value types and pages
work; Android audio devices/playback and the legacy QGLPixelBuffer API are
not qualified. WebKit, Phonon, OpenSSL, D-Bus and ICU are disabled.

The classic C/POSIX locale is qualified; wide-character libc++ support is
disabled. The shared legacy runtime contains the x86 wait4 adapter verified
for Qt 5, while the stock Bionic generic syscall defect remains unwrapped
for arbitrary consumer code. No exhaustive C++23, arbitrary device GPU or
all newer Android releases claim is made.

Raw evidence: `artifacts/qt4-android-gingerbread-x86/`, especially
`sdk-reports/`, `sdk-suite-2/`, `final-results.json`, `apk-architecture-final.json`
and `screenshots.json`. Native/repeat/CMake/Docker logs and the separate
shader diagnostic remain under `build/qt4-android-x86/`. APK history is retained
by hash. Local SDK images, guest media and development signing keys are not
release assets. No local security suites were run and nothing was pushed.

| APK | SHA256 |
| --- | --- |
| bootstrap | `a2b5c1a045335440bb122b1b7e9f407f81de3604b1069969fd8d2161f1bb2a9b` |
| strict | `26ff34efcacf0de828dd273aaa7c8dcc21153facd613b7eb03b0f599d3ed073b` |
| core | `bc9f2be99446a2eee0dc2640623d2b9e079e907fc4130c8c0732ded68de9a5b3` |
| selftest | `800a1040f254c53bcd6b69c44c0c0348c963a402a8fef559f314b17337d84aa1` |
| widgets | `5cac7fddd0872be8a753c93d71cf61d706070028bd764f8f1b77a00a4c81bde8` |
| graphics | `2d1a8a18898bcd06da5fbc421491b32262be6fd0e261a817de4b73c644d13676` |
| painting | `0ac944a6c02a7a9cb64c506784162dcf5c7e226f4780d35d1965d2d49fe397cd` |
| multimedia | `6b54f2641e4152f986ff8b086f72c69d8759575166573364e18b7d9d586d0be0` |
| gl | `a4921b01fdae8472fa610e9a39b7438958192e8f30f165c6d584b1187aba0f8a` |
| qml | `e8bd34c9d88073d5d0f3c4dd0b2ef505b1d5b181b56a885caac8ab4ed2761224` |
| network | `633b68fa22012f0eb7c2f71069d61db98572e10a32276a5fdd263292bce49a48` |
| quick | `994f728bbf96aba339ad39ef4ba7463b03c53253f34819b94c036a74c82ab4e1` |
