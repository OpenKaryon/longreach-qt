# Experimental Qt 4.8.7 for Android API 21 x86_64

This profile builds a static Qt 4 SDK and JNI APK clients for Android 5/API 21,
`x86_64`, with upstream LLVM 21.1.8 and libc++. The original
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

Only `sdk` fetches source inputs and builds Qt. Its Docker stage is explicitly
`--target sdk`; the Dockerfile's default stage remains the original host tools
used by the API 4 build and bootstrap callers. The Docker directory contains
only `Dockerfile`.

`examples` inspects an existing SDK's Qt/LLVM/API/ABI labels and uses its immutable
image ID. A missing or incompatible image fails before compilation; it never
starts an implicit SDK build. It exports the installed producer reports and
builds twelve JNI libraries, including all eight common applications, in C++23.
They use their existing qmake projects and shared JNI adapters. Retained native
clients relink when the installed archive manifest changes, even when copied
cache timestamps are newer than those archives; compilation objects remain reusable.

`package` requires matching SDK/example IDs and all twelve recorded native
hashes before replacing any APK. It uses host Java/Android tools, the pinned
platform 35 jar, manifest minimum/target API 21, and local development v1 signing.
Previous APKs are retained by hash under the ignored output directory.
`test` only fetches pinned emulator media and runs saved APKs. It never compiles
or packages. Each `-RunName` must be a new directory.

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
The x86_64 CPU baseline is `-march=x86-64-v2`.

The selected SDK contains fourteen modules: Core, Gui, Network, Sql, Xml, Svg,
Script, Declarative, Test, Multimedia, OpenGL, ScriptTools, XmlPatterns and
Qt3Support. The minimal platform, SVG image plugin and four Qt Quick 1 labs
plugins are static. Producer reports verify every target archive's ELF class
and machine, effective configuration, source archive, compatibility patches,
patched sources and C++ runtime.

A change in effective configure flags invalidates affected target module/plugin
objects. Source-only corrections retain incremental objects; repeating an
unchanged SDK configuration does not rerun configure or target compilation.
Installed qconfig metadata is refreshed when configuration changes.

## Emulator cases and limits

The runner uses the pinned Android 5.0.2/LSY66K x86_64 r05 guest and official
Emulator 32.1.11/build 9536276, software CPU/GLES, 1 GiB RAM and no visible window
or host input capture. Build containers use two jobs, two CPUs and 3 GiB RAM.
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
for measured counts and limitations.
