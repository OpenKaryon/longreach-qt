# Qt 6 Android API 21 x86 with LLVM 21.1.8

Built and verified 2026-11-20 UTC. This is a source SDK target; local SDK,
Android images, APKs and signing keys are not release attachments.

## Result

The full Qt 6.8.5 SDK, all eight shared examples/APKs and both gallery GUI
cases passed on Android 5.0.2/API 21 x86. Installed-SDK C++23 passed
**25 PASS, 0 FAIL, 0 SKIP**. The complete `sdk-suite-3` contains eleven
required cases, with native exit 0 and each result bound to its current APK
SHA256 and the immutable SDK used to build it.

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

Ordinary SKIPs describe unavailable platform/module behavior. They do not
replace any of the 25 mandatory C++23 checks. The Widgets pages mosaic and
QML gallery PNGs were also inspected: controls, text, tables and shapes render.

## Toolchain, SDK and provenance

The target is `i686-linux-android21`, ABI `x86`, with installed Qt prefix
`/opt/qt6-android-x86-llvm`. Compiler flags are
`-march=i686 -mssse3 -mstackrealign -mfpmath=sse`. The
[Android x86 ABI](https://developer.android.com/ndk/guides/abis#x86)
requires SSSE3 and 16-byte stack alignment; SSE4 and AVX are optional.

NDK r27 supplies platform headers, CRT objects, link stubs and Android helper
sources. The C++ runtime comes from upstream LLVM 21.1.8 sources, not the stock
NDK libc++. Installed qmake reports Qt 6.8.5, QMake 3.1 and the correct prefix.
The SDK contains **137 root Qt libraries**, ten Android JARs and **290 validated
ELF32/i386 shared libraries** including plugins, QML and runtime. These have
SysV hashes, no native ELF TLS or newer packed relocations, and no GNU/host
runtime dependencies or stock `__ndk1` ABI references. Provenance records
28 platform/CPU-feature inputs and 1569 effective platform headers.

Final consumer image: `longreach-qt6-android-lollipop-x86:llvm21`.

`sha256:9bd3339a92f445fc70e4265021275c4ffcf974132ce51e0d547667c3f1bcce0b`

The consumer compiler is the pinned source-built upstream LLVM 21.1.8 at
`/opt/llvm-21/bin/clang-21`, executable SHA256
`6c31c191790134904d2b562c4fb82114e3d6540f0f860a253a05bd2d412c94c4`.
The shared source archive pin is
`4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142`.

The native SDK's object cache was started before the Android audit and retained
through its completion. That producer uses the upstream apt Clang 21.1.8 binary,
SHA256 `82481792aef943c1750ae5fd71e5a5737212741337debd0fe5d28bd82dd018e9`,
from immutable tools image
`sha256:e56025d7351cc0ce9c69a6c4fa24ecad711ee2f9582420e040146faaa6a14d6b`.
It is not a fresh native SDK build with the later source-built compiler recipe.
The final clients use the source compiler; `sdk-build-provenance.json` and
both compiler logs preserve that distinction.

The installed/shared runtime SHA256 is
`4b820ad6e3501b4d11e9cbaf7c0d6578e2ead1fc3f8c81271014810bf6c513ff`.
Every DSO in all eight current APKs was checked as ELF32/machine 3, with only
`lib/x86/` native entries. All APKs contain this exact runtime and match their
recorded APK hashes.

## Runtime and link corrections

The initial runtime passed the canonical 25 behavior checks in `cxx23-probe-1`,
but the real Qt/OpenSSL link probe exposed missing generic `__atomic_*`
functions on 32-bit x86. The producer now compiles the pinned compiler-rt
`atomic.c` with its pthread backend into the shared libc++ runtime. SDK
libraries share one lock table; no GNU/NDK atomic runtime is added. The five
generic entry points are checked as dynamic exports.

This repair compiled one C source and relinked the retained runtime. The
result above passed **25/0/0** again in `cxx23-probe-2`. A separate ordinary
probe passed 16-byte atomic store/load/exchange and a two-thread CAS handoff.
That regression does not change the canonical 25-check language manifest.
The final installed-SDK run uses the same repaired runtime.

OpenSSL's i386 assembly also requires its static archive symbols, including
`OPENSSL_ia32cap_P`, to stay private within each DSO. Both shared-library and
MODULE linker flags now exclude `libssl.a`/`libcrypto.a` from public exports.
The actual OpenSSL configuration probe and TLS backend plugin then linked.
The PIE pthread/shared-library link-kind regression passed as well.

## Pinned guest and emulator

The official `x86-21_r05.zip` contains Android 5.0.2/LSY66K, API 21 and x86 only.
Its 208212529 bytes match Google's SHA1 `00f0eb0a1003efe3316347f762e20a85d8749cff` and SHA256
`2a7d1a01a4a455b989353d16c3f2bc427b6e133300072c790c7650e5e0080095`. Metadata:
[Google system-image repository](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml).

The official Emulator 32.1.11/build 9536276 archive has SHA256
`7720a38136399a93af4a3da57715d69f26d7b86c74d60ea016162e11f1fae439`. Both archives are locked in
`scripts/fetch/locks/qt6-android-api21-inputs.json`.

The final guest uses the image's Linux 3.10 `kernel-ranchu`, a run-owned QEMU2
AVD, a Conroe CPU model, **one guest core** and 1 GiB RAM. CPU acceleration is
off and SwiftShader supplies host-side GLES. Vulkan and file-backed quickboot
are disabled; both legacy GPU options select software GLES. Qt Quick retains
its normal GLES backend. Runs are headless without host keyboard/mouse capture.
Captured `/proc/cpuinfo` confirms one processor, SSSE3, and no SSE4.1/SSE4.2/AVX.

## Retained failures and controller changes

`sdk-suite-1` passed strict C++23 25/0/0, ordinary selftest 293/0/43 and Widgets
91/0/4. It stopped before Graphics launch when a host adb connection to the
dedicated port 5048 timed out. The existing Platform Tools 37.0.1 server was
still alive/listening and a later health query succeeded; the socket failure's
cause was not isolated. Only the task-private server was restarted, after
owned guest cleanup. Global adb on 5037 was left untouched.

`sdk-suite-2` then hit a kernel panic during a normal two-core TCG boot,
about two seconds after kernel startup, before any APK ran. Its kernel log
is retained. The old direct `adb getprop` blocked behind the failed guest;
the owned query and emulator were stopped without touching other processes.

The x86 profile now selects one guest core as a workaround for that observed
boot failure; other ABI core counts remain unchanged. The old kernel's
underlying SMP/emulation defect was not fully isolated. The shared readiness
helper bounds each boot query to five seconds and total readiness to 300
seconds, detects a recorded kernel panic or exited guest, and stops only its
own timed-out client. The `scripts/tests/android/test-android-wait-boot.ps1` real-child fixture passed
successful readiness,
nonzero refusal, hung-client termination/deadline, panic detection, exited
guest handling and preservation of an unrelated control process.

`sdk-suite-3` cold-booted in 38.4 seconds with zero query timeouts, then passed
all eleven cases above with the unchanged SDK and APK bytes. Case logs retain
launch markers and fatal-cleanup checks; a partial diagnostic never becomes
a complete-suite report.

A second fresh one-core boot (`single-core-coldboot-confirmation`) completed in
43.2 seconds with 0 query timeouts and repeated strict C++23
**25/0/0** plus QML GUI **3/0/0** with identical APK hashes. This focused
confirmation leaves the complete eleven-case report bound to `sdk-suite-3`.

## Cache preservation and phase integrity

The retained native producer completed all 9008 Ninja steps and installation,
exiting 0 without an OOM. Refreshing the audited stack applied 40 patches with
0 changed source files. The subsequent incremental build ran 10 actions,
including one generated-UI-dependent Qt Tools object and its link. Native
SDK/runtime/source caches were preserved. Shared LLVM tools were refreshed
through Docker's cache.

The first consumer run compiled/deployed all eight examples, then correctly
refused to overwrite an unmarked `sdk-packaging/` directory that had been
exported manually from the native producer. It exited 1 with an incomplete
generation. That producer export was preserved within the artifact root as
`native-sdk-packaging-before-examples/`; examples mode resumed the same
container/object cache and completed. The ownership guard was not relaxed,
and the SDK was not rebuilt. Completed examples/APK manifests bind Java,
runtime, native deployments and APKs to the selected immutable SDK.

The current phase-routing and failed-generation fixtures passed, including
x86 versus x86_64 image rejection and packaging preflight. PowerShell syntax
checks and the new readiness fixture passed. Common application sources and
old-standard guards were preserved.

## Limits and evidence

This is behavior coverage, not complete C++23 standard-library conformance.
Physical cameras/audio/Bluetooth/NFC/XR and stdio files above 2 GiB were not
qualified. QtWebEngine, Wayland, Vulkan, DBus, glib and ICU remain excluded;
Hunspell correction and QDoc's Clang-based parser are not part of this SDK.
Ordinary platform SKIPs remain explicit in captured stdout.

Local evidence is under `artifacts/qt6-android-lollipop-x86/` and
`build/qt6-android-x86/`: SDK/module/ELF/input provenance, compiler logs,
completed generation manifests, APK hashes, `final-results.json`,
`sdk-suite-3/`, both earlier failed runs and gallery PNGs. No local security
suites, push or new tag were invoked. All SDK builds, client compilation,
packaging and guests ran serially; compilation used 2 CPUs / 3 GiB and one
SDK link job.
