# Qt 6 Android API21 ARM64 with LLVM 21.1.8

Investigation and build started 2026-11-19 UTC. This is a source SDK target;
binary SDK images, Android system images and local signing keys are not release
attachments.

## Status

The standalone C++23 probe and the installed-SDK strict selftest both passed
**25 PASS, 0 FAIL, 0 SKIP** on Android 5.0.2/API21 ARM64. The full Qt 6.8.5 SDK,
all eight shared examples/APKs and both GUI rendering cases passed. The final
`sdk-suite-2` contains all eleven required cases and binds each result to its
current APK SHA256. Ordinary platform/module SKIPs are recorded separately.

## Confirmed toolchain and guest

- Upstream LLVM 21.1.8 builds libc++, libc++abi, libunwind and compiler-rt.
  NDK r27 supplies only platform headers, CRT objects, link stubs and helper
  sources. Its compiler and stock libc++ are not used.
- Target triple: `aarch64-linux-android21`; ABI `arm64-v8a`.
- The official `arm64-v8a-21_r04.zip` image identifies Android 5.0.2, API21,
  build LSY66K and a pure ARM64 ABI list. Its SHA256 is
  `6f9f8ab64641ccbea92a02cc85c130a60c3464b87aa9d49952a8d8292f84d073`;
  it also matches Google's published SHA1
  `c4375f1b4b4cd21a8617660e25f621cedcbd8332`.
- Windows SDK Tools 25.2.5 SHA256:
  `da1a0bd9bb358cb52a8fc0a553a060428efe11151e69b9ea7a5cbacb27cf1c7c`;
  official SHA1 `a7f7ebeae1c8d8f62d3a8466e9c81baee7cc31ca`.
- All SDK and emulator inputs are pinned in
  `scripts/fetch/locks/qt6-android-api21-inputs.json`.

The successful guest uses the archive's `kernel-qemu` 3.10, which is a ranchu
kernel for ARM64. Its newer `kernel-ranchu` 3.18 did not boot with these Tools 25
binaries. Tools 24's ARM64 launchers failed before usable Android startup; the
installed Emulator 37 rejects ARM64 on this x86_64 Windows host. Those failures
are host-emulator compatibility observations, not Qt runtime failures.

The runner selects QEMU2 through a task-owned AVD, with relative image paths,
1 GiB RAM, no snapshots and a headless display. Guest files, AVD configuration,
serial logs and results remain within a unique run under the artifact root.
The old QEMU2 backend rejects the `-no-audio` translation; the ARM64 AVD disables
audio inputs/outputs instead. No host keyboard or mouse capture is used.

## Standalone C++23 evidence

`cxx23-probe-1` passed **25 PASS, 0 FAIL, 0 SKIP**, native exit0. The shared
probe reports Clang21.1.8, libc++ 210108 and `__cplusplus=202302`. It uses
`scripts/tests/qt6-llvm-probes/main.cpp` and `tests/common/moderncpp_checks.h`;
there is no second Android-specific implementation of the checks.

Evidence is under `artifacts/qt6-android-lollipop-arm64-v8a/`:

- `cxx23-probe-1/cxx23.stdout`, guest properties and logcat;
- `probe/cxx23-probe`: SHA256
  `e6eb2e44729438489f3640c14868d601a1453736aa724d02e69a7bafd03e5fe9`;
- `probe/libc++_shared.so`: SHA256
  `fa08e29dc1ee5cb12af97b2ca60b25c1b15dd8d198ab7dd648d48395f78e69db`.

This covers the required25 behaviors, including stop/join, cancellation,
thread-local destruction, atomic wait/notify, unwinding, Unicode filesystem
round-trip, format/print and expected error propagation. It does not claim
complete C++23 library conformance.

## SDK compatibility checks

While the full SDK was compiling, the API21 ELF checker passed on the first
73 built target libraries, including the shared LLVM runtime. All were the
expected AArch64 ELF64 objects, with SysV hashes, no native ELF TLS and no
new packed relocations. The runtime SHA256 matched the standalone 25/25
probe exactly. This early subset does not replace the final SDK inventory.
The local record is `build/qt6-android-arm64-v8a/partial-api21-elf.json`.

## Producer changes and focused checks

The existing `docker/qt6/android/Dockerfile` and helper scripts now select
ARMv7 or ARM64 through `ANDROID_ABI` / PowerShell `-Abi`. ARMv7 remains the
default. Installed compiler drivers capture their target metadata, SDK image
labels identify the ABI, and output/image names isolate the new ARM64 target.
APK packaging and result collection select the same ABI explicitly.

Two actual ARM64 issues were corrected before SDK compilation:

1. Whole-archiving compiler-rt together with libc++ produced duplicate
   `__muloti4`. Required builtins now follow the whole C++ archives, with
   emulated-TLS entry points retained explicitly.
2. The old driver always linked a shared library. Qt CMake's `-fPIE` pthread
   check requires a PIE executable on AArch64. The driver now selects the
   correct link kind, CRT objects and Android dynamic linker. Both PIE and
   shared pthread links pass `scripts/tests/android/android-api21-driver.sh` in the
   Docker runtime stage, without forcing `Threads_FOUND`.

The independent sdk/examples/package/test modes remain separate. Lightweight
routing checks pass for default ARMv7 behavior, cross-ABI image rejection,
ARM64 tag selection and ABI-specific deployment packaging. No second SDK build
or emulator runs in parallel.

## Reproduction

The shared target guide describes prerequisites and each phase:
[Qt6 Android API21](../targets/qt6-android-lollipop.md).

```powershell
./scripts/build/qt6-android.ps1 -Abi arm64-v8a -Mode sdk -AndroidSdk $androidSdk
./scripts/build/qt6-android.ps1 -Abi arm64-v8a -Mode examples
./scripts/build/qt6-android.ps1 -Abi arm64-v8a -Mode package -AndroidSdk $androidSdk
./scripts/build/qt6-android.ps1 -Abi arm64-v8a -Mode test -AndroidSdk $androidSdk -RunName sdk-suite-1
```

The successfully built SDK image is
`longreach-qt6-android-lollipop-arm64-v8a:llvm21`, SDK prefix
`/opt/qt6-android-arm64-v8a-llvm`. The final inventory contains 137 Qt module libraries, 290 checked AArch64
ELF64 libraries and ten Android JARs. Qmake reports 6.8.5 and the expected SDK prefix.

SDK image identity (Docker inspect and `sdk-image-id.txt`):
`sha256:714aa397f8675792ad76de42a06b7da6bee50d7afad5c5218b664af639fcc4e1`.
The examples phase records the same immutable SDK ID. The unmodified first SDK
was `sha256:485c6ee52918a29687890b6b33ba52a030d6a4447b0651541856f05b4fb2c445`;
the final SDK incorporates the loader fix described below.
All SDK producer checks completed with exit0 before the separate examples phase.

## API21 QML plugin loader investigation

The first suite passed strict C++23 (25/0/0), qt-selftest (292/0/43),
Widgets (91/0/4), Graphics (32/0/0), Painting (16/0/0), Multimedia (4/0/0)
and OpenGL (58/0/1). QML reported 34/1/5: its shared visual QML file
could not load the QtQuick Controls plugin. Real Quick3D rendering and the
native OpenGL texture check passed. The later Network/GUI cases were not reached.

A raw `dlopen` probe obtained the first error hidden by Qt's bundle-name retry:
the installed plugin's absolute path is 128 bytes and the Android 5 LP64 linker
rejects it as too long. Loading the exact same plugin by basename through its
normal library search path succeeds with NOW, LAZY and GLOBAL flags.
This matches [AOSP's Android 5.0.2 loader implementation](https://raw.githubusercontent.com/aosp-mirror/platform_bionic/android-5.0.2_r1/linker/linker.cpp).

The new Android patch retries an existing absolute library path of at least
128 encoded bytes by basename, only on API21/22, before Qt's original bundle
retry. The original flags, resources and QML coverage are retained.
`RTLD_NODELETE` was investigated separately: the old loader rejects it, but Qt
already guards that flag by Android version, so it was not the QML failure.

Local evidence: `sdk-suite-1/`, `qml-debug-1/`, `dlopen-probe-1/`,
`dlopen-plugin-1/` (absolute path failure) and `dlopen-plugin-2/` (basename
success). QtCore was rebuilt incrementally from the saved successful Qt build stage.
Exactly one C++ source changed and compiled; Core was relinked, then the final
prefix and producer reports were staged into the SDK image. All producer checks
passed again. A repeat build preserved patch/source timestamps and compiled no
C++; only five standard utility-to-APK copy steps ran. The normal Docker recipe
applies the same patch on clean builds. `qt-patch-state.json` records all 40
patch hashes and stack fingerprint
`a931d3522ec85560b059ad6139587b9ecf7d7111b25029e93313d086c1b6b48d`.

## Final installed-SDK runtime results

The fresh ARM64 guest ran one case at a time with default real GLES; no Qt Quick
software backend was forced. Every native result was0 and logcat contained no
fatal Java/native cleanup failure. The collector verified all eleven names,
Android release/API/ABI and the SHA256 of each current APK.

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

The ordinary SKIPs cover removed Qt5 interfaces, absent ICU/Wayland/Vulkan,
non-Android graphics backends and unavailable physical-device capabilities.
They do not affect the separate mandatory C++23 run. Quick3D frame rendering
and native OpenGL texture adoption passed.

The Widgets contact sheet and QML Controls gallery PNG were inspected visually:
controls, text, geometry and item views rendered. Evidence is in
`sdk-suite-2/widgets-gui/files/widgets-gallery-pages.png` and
`sdk-suite-2/qml-gui/files/quick-gallery.png`.

All eight APKs contain only AArch64 ELF64 libraries. Each includes the exact
shared libc++ from the successful standalone probe. Local inventories:
`apk/packages.json`, `apk-architecture.json`, `final-results.json`,
`final-results-table.md` and `qt-patch-state.json`.

| APK | SHA256 |
| --- | --- |
| gl-heavy-gallery.apk | `78bae143cc06a15f26542e0827cf89e2ebd75a9be1479e9b67c036bae034d542` |
| graphics-gallery.apk | `02b769e0127127f3387fc64b1d77506de524a1e1d86f44ea65630cfe61c2aa6d` |
| multimedia-lab.apk | `3baafb01c3090a8065e9b6f1e0b5c240f0a7ba1eb4922e6592a184c3bd0f6f87` |
| network-gui.apk | `54d3d0fc87ed3458529a167531e9d731ca05b043ecdc4f0db0c8f4855f6b7b83` |
| painting-lab.apk | `de9e8f8a5208474a2565b2dd9666697bdff5aed9a66292fbe417711363754e71` |
| qt-selftest.apk | `572038ec28833df1c83018f1cea9b0b8264156a395349d89e2b617d22e53763f` |
| quick-qml-gallery.apk | `d58b52dcba2deb6a9feeff6052de935c858a194a1b5b9567549e8cb7474f0537` |
| widgets-gallery.apk | `dc91f1a0349d7fc422ddc42d932b6c2b6b76638de6d09b83552facf8b4ec1b02` |

## ARMv7 default-profile regression

The shared runtime/driver changes were checked separately on the unchanged
ARMv7 floor. The `runtime` Docker target built with `ANDROID_ABI=armeabi-v7a`;
its PIE pthread probe and shared-library link checks passed. The exact shared
25-check C++23 source then passed **25/0/0**, native exit0, on a fresh pinned
Android5.0.2/API21 ARMv7 guest. The original full ARMv7 SDK/tag was preserved.
No full ARMv7 Qt build was needed for this runtime/driver regression.

Evidence: `artifacts/qt6-android-lollipop-armv7-runtime-regression/`, especially
`cxx23-runtime-regression/cxx23.stdout` and guest properties. Tested runtime
SHA256: `5e96ba680a7945cfeca09a0cab00562c7bb15559ef4ceadb504667ec809c0646`.
The regression image is `longreach-qt6-android-lollipop:runtime-regression`.

## Scope

Only the pinned Android5.0.2 emulator image was run; Android5.0.0 and physical
ARM64 devices were not tested. Audio/camera/Bluetooth/NFC/XR hardware and files
larger than2GiB remain outside this validation. This is behavior coverage, not
exhaustive Qt or C++23 conformance. Security/CVE tests were not run; no binary
release, push or new tag accompanies this target.
