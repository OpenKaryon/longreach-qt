# Experimental Qt 4.8.7 for Android API 21 x86_64 and ARM64

The [make and build-all interface](../android-build.md) provides SDK and ready-APK
`-examples` targets. The individual PowerShell phases below remain available;
use the Android runners to launch saved APKs.

Emulator test mode requires a Windows 10+ host, PowerShell 7 and Python 3.11+.
The [host ownership and completion contract](android-artifacts.md#host-process-ownership-and-completion-receipts)
applies to new qualification; older runs without those receipts stay historical.

This profile builds a static Qt 4 SDK and JNI APK clients for Android 5/API 21,
`x86_64` or `arm64-v8a`, with upstream LLVM 21.1.8 and libc++. The original
[Android 1.6/armeabi profile](qt4-android-donut.md) remains the default.
It does not use an NDK compiler or stock NDK C++ runtime. The same phase
interface also supports [Android API 10 x86](qt4-android-gingerbread.md).

## Build and run

Use Docker Desktop with Linux containers, PowerShell 7, Python 3.11+, JDK 17/21,
Android SDK platform 35, Build Tools 36.0.0 and Platform Tools. Set
`ANDROID_HOME` or pass `-AndroidSdk` to each command. Run each phase separately:

```powershell
./scripts/build/qt4-android.ps1 -Abi x86_64 -Mode sdk
./scripts/build/qt4-android.ps1 -Abi x86_64 -Mode examples
./scripts/build/qt4-android.ps1 -Abi x86_64 -Mode package
./scripts/build/qt4-android.ps1 -Abi x86_64 -Mode test -RunName sdk-suite
```

For ARM64 use `-Abi arm64-v8a` in each command. Its default image is
`longreach-qt4-android-lollipop-arm64-v8a:llvm21`, installed prefix
`/opt/qt4-android-arm64-v8a-llvm`, output directory
`artifacts/qt4-android-lollipop-arm64-v8a/`.

Only `sdk` fetches source inputs and builds Qt. Its Docker stage is explicitly
`--target sdk`; the Dockerfile's default stage remains the original host tools
used by the API 4 build and bootstrap callers. The Docker directory contains
only `Dockerfile`.

`examples` inspects an existing SDK's Qt/LLVM/API/ABI labels and uses its immutable
image ID. A missing or incompatible image fails before compilation; it never
starts an implicit SDK build. It exports the installed producer reports and
builds twelve JNI libraries, including all eight common applications, in C++23.
They use their existing qmake projects and shared JNI adapters. Retained native
clients relink when actual installed archives, CRT/builtins, runtime libraries,
platform link inputs or the linker change, even when cache timestamps are newer
than those inputs; unchanged compilation objects remain reusable.

`package` requires matching SDK/example IDs and all twelve recorded native
hashes before replacing any APK. It uses host Java/Android tools, the pinned
platform 35 jar, manifest minimum/target API 21, and local development v1 signing.
The native generation is reserved before compilation and sealed only after
all twelve recorded libraries match. Packaging captures its Java/tool inputs
and an already-created signing key, then compares the embedded JNI/runtime
bytes in every APK against that completed generation. Failed or partial phases
have no accepted completion receipt. Previous APKs are retained by hash under
the ignored output directory.
`test` only fetches pinned emulator media and runs saved APKs. It never compiles
or packages. Both the test-mode wrapper and standalone runner reject APKs
bound to an older native generation, including rebuilds with the same SDK ID.
The collector binds each case to the completed native/package receipts.
Each `-RunName` must be a new directory. Older unbound output directories need
a complete examples/package refresh before a new run; historical evidence is
not rewritten.

The image is `longreach-qt4-android-lollipop-x86_64:llvm21`, prefix
`/opt/qt4-android-x86_64-llvm`; outputs default to
`artifacts/qt4-android-lollipop-x86_64/`. Installed host qmake, moc, rcc, uic,
headers, mkspecs, static libraries and `toolchain.cmake` support external clients.
Source/object trees are absent from the final SDK image.

## Runtime and modules

API 21 reuses the shared LLVM/Bionic producer and pinned platform input lock.
NDK r27 supplies platform headers, CRT, link stubs and helper sources. Qt source
and LLVM archives have a separate Qt 4 lock. Qt libraries build as GNU++98;
client applications select GNU++23 with `-fexperimental-library`.
The x86_64 CPU baseline is `-march=x86-64-v2`. ARM64 targets
`aarch64-linux-android21` and uses Qt 4's portable generic atomic backend.
The 4.8.7 JavaScriptCore sources already select AArch64 and the 64-bit JSValue
layout. JavaScript JIT is disabled for both profiles.

The selected SDK contains fourteen modules: Core, Gui, Network, Sql, Xml, Svg,
Script, Declarative, Test, Multimedia, OpenGL, ScriptTools, XmlPatterns and
Qt3Support. The minimal platform, SVG image plugin and four Qt Quick 1 labs
plugins are static. Producer reports verify every target archive's ELF class
and machine, effective configuration, source archive, compatibility patches,
patched sources and C++ runtime.

The public Docker `qt-build` stage mounts an ABI-specific BuildKit cache at
`/work` with exclusive sharing. SDK fingerprints include configure flags,
actual compiler binary/version, runtime wrappers/target settings, mkspec and
runtime/platform headers. A change invalidates affected target module/plugin
objects. Source-only corrections retain incremental objects; repeating an
unchanged SDK configuration does not rerun configure or target compilation.
Prepared-source receipts bind the source archive, source helper and selected
patch bytes. A changed recipe is applied to a pristine temporary tree before
changed source files are synchronized into the retained tree. Removed patches
are reverted; unchanged generated files and objects stay in place. Failed patch
application leaves the live tree intact, and interrupted synchronization is
retried before a new receipt is accepted. Unrecorded older trees reconfigure
once. Configuration/project/mkspec inputs also participate in the SDK key.
Installed mkspecs, features and qconfig metadata are refreshed. Producer reports
reject a source recipe or patched file that differs from its prepared receipt.

Public examples mode retains a named client `/work` volume per ABI and output
root. Its compile key also includes installed Qt headers and host qmake/moc/rcc/uic.
After qmake evaluates the project, its effective compiler commands, defines,
C/C++ flags and include paths participate in the object key. A changed compile
key cleans the affected client after qmake. Separate link keys include actual
Qt/plugin archive bytes, runtime/CRT/builtins, selected API platform stubs,
linker bytes and effective link flags/libraries. Link-only changes relink while
retaining compilation objects. Failed builds do not publish successful cache
keys; the core SDK probe uses the same retained-client rules. Cache storage lives
outside the final SDK image; clearing Docker build cache or that client volume
naturally removes the corresponding incremental state.

## Emulator cases and limits

The runner uses the pinned Android 5.0.2/LSY66K x86_64 r05 guest and official
Emulator 32.1.11/build 9536276, software CPU/GLES, 1 GiB RAM and no visible window
or host input capture. Build containers use two jobs, two CPUs and 3 GiB RAM.
The ARM64 profile uses the pinned Android 5.0.2/LSY66K r04 guest, Tools
25.2.5 and a software-emulated Cortex-A57 with 1 GiB RAM and GLES.
Builds and guests must run sequentially.

The full suite includes bootstrap, strict C++23, an installed-qmake QtCore
consumer, all eight shared ordinary examples, and Android gallery instrumentation.
The strict gate requires exactly 25 PASS, 0 FAIL and 0 SKIP. Ordinary examples
report their platform/version limitations separately. A `-Profiles strict,quick`
subset is useful for focused checks but never creates full-target evidence.

Qt Quick 1 and Widgets use the existing raster/Canvas bridge; this profile does
not provide QtActivity or native Android widget window integration. The minimal
platform supports real GLES2 pbuffer contexts for offscreen QGLWidget/FBO/shader
checks. Native onscreen GL window integration and the legacy QGLPixelBuffer API
are not provided. QtMultimedia value types, video surfaces and rendered example
pages are included; Android audio-device/playback integration is not provided.
WebKit, Phonon, OpenSSL, D-Bus, ICU and desktop integration backends are disabled.
The minimal font database maps generic families to Android's Roboto, Noto Serif
and Droid Sans Mono instead of selecting a clock-only font. The shared selftest
checks that the default font contains ASCII letters and digits. Qt 5/6-only APIs
remain explicit ordinary-example SKIPs.

Launch-marker boundaries preserve raw logcat while excluding earlier package
manager logs from the current case. Current native/Java fatal errors still fail
the suite. The final collector checks all twelve APK hashes, ABI/runtime
identity, guest properties, native/instrumentation results and gallery PNGs.
See the [target result record](../results/qt4-android-lollipop-x86_64-llvm21-20261120.md)
for measured x86_64 counts and limitations. The
[ARM64 result record](../results/qt4-android-lollipop-arm64-v8a-llvm21-20261121.md)
records its independent qualification.


See [Android artifact generations and coverage](android-artifacts.md) for phase
ownership, packaging receipts, ABI preflight, per-target coverage limits and
the private ADB environment used in local reproduction.


The JNI case remains resident until explicit package release. The runner now
saves and checks logcat after each force-stop/uninstall, before clearing it for
the next profile. A successful host-bound final-log capture and unchanged case
hashes are also required by full and selected runs. See
[resident Qt4 cleanup evidence](android-artifacts.md#resident-qt4-case-release-and-final-capture).
These source/fixture changes do not requalify the historical target results.
