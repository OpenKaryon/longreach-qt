# Qt 6 Android API 21 x86_64 with LLVM 21.1.8

Built and verified 2026-11-20 UTC. This is a source SDK target; local SDK,
Android images, APKs and signing keys are not release attachments.

## Result

The full Qt 6.8.5 SDK, all eight shared examples/APKs and both gallery GUI
cases passed on Android 5.0.2/API 21 x86_64. Installed-SDK C++23 passed
**25 PASS, 0 FAIL, 0 SKIP**. The complete `sdk-suite-4` contains eleven
required cases, with native exit 0 and each result bound to its current APK
SHA256 and the immutable SDK used to build it.

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

Ordinary SKIPs describe unavailable platform/module behavior. They do not
replace any of the 25 mandatory C++23 checks.

## Toolchain and SDK

- Upstream LLVM 21.1.8 builds libc++, libc++abi, libunwind and compiler-rt.
  NDK r27 supplies platform headers, CRT objects, link stubs and Android helper
  sources. The compiler and C++ runtime come from the matching LLVM sources.
- Target: `x86_64-linux-android21`, ABI `x86_64`, installed Qt prefix
  `/opt/qt6-android-x86_64-llvm`.
- The explicit `-march=x86-64-v2` baseline matches the
  [Android x86_64 ABI](https://developer.android.com/ndk/guides/abis#x86_64).
  AVX is not required.
- Qmake reports 6.8.5 and the correct installed prefix; the compiler reports
  21.1.8. The SDK contains **137 Qt module libraries** and ten Android JARs.
- All **290 ELF64 x86-64 libraries**, including the shared C++ runtime, passed
  the API 21 loader checker: SysV hash tables, no native ELF TLS or newer
  packed relocations, and no GNU/host runtime or stock NDK C++ ABI references.
- Producer provenance records 28 platform/CPU-feature inputs and 1569
  effective platform headers.

Final image: `longreach-qt6-android-lollipop-x86_64:llvm21`.

`sha256:8d1d5b19afb975c739994a0ffcf36a688e6ccf8a4fd2312bce4e828ceb40944b`

The original successful native build, source/object cache and installed SDK
were retained while the emulator/controller corrections were tested. All
successful comparisons and the final suite use the same SDK and APK bytes.

The shared LLVM C++ runtime SHA256 is:

`8b03afda56a3f0bc3fc0309b4edb1f5b08ee29b77d68fe5a1a03393d60563dc0`.

Every packaged DSO in all eight current APKs was checked as ELF64/machine62;
all APKs contain this same runtime. APK hashes also match `apk/packages.json`
and the complete result collector.

## Pinned emulator and system image

The official `x86_64-21_r05.zip` is Android 5.0.2/LSY66K, API 21, primary ABI
x86_64 and secondary ABI x86. Its 292623982 bytes match Google's published
SHA1 `9078a095825a69e5e215713f0866c83cef65a342` and recorded SHA256:

`b652297c0733cced8e9507e5018d78f56b87141c47e4d7ada60f495469f76d49`.

Metadata: [official Google system-image repository](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml).

The successful Windows emulator is **32.1.11.0/build9536276**, archive
`emulator-windows_x64-9536276.zip`, 333000964 bytes. Its published SHA256 is:

`7720a38136399a93af4a3da57715d69f26d7b86c74d60ea016162e11f1fae439`.

Source: [official Emulator download archive](https://developer.android.com/studio/emulator_archive).
Both archives are pinned in `scripts/fetch/locks/qt6-android-api21-inputs.json`.

The guest uses the archive's Linux 3.10 `kernel-ranchu`, a run-owned QEMU2 AVD,
a Nehalem CPU model, two guest cores and 1 GiB RAM. CPU acceleration is off;
SwiftShader supplies host-side GLES. Vulkan and file-backed quickboot are
disabled. The legacy `on`/`mesa` GPU options both select this software GLES
renderer for x86_64. Qt Quick uses its normal GLES backend. Runs are headless
and do not capture the host keyboard or mouse.

## Behavior coverage and corrections

The standalone probe passed 25/0/0 before the SDK build. It reports Clang
21.1.8, libc++ 210108 and `__cplusplus=202302`, using the same
`tests/common/moderncpp_checks.h` as the installed-SDK example. The mandatory
checks cover thread/stop-token behavior, atomic wait, thread-local destruction,
filesystem, unwinding, format/print and expected error propagation. This is
behavior coverage rather than complete C++23 library conformance.

Legacy SDK Tools 25.2.5 reproduced a TLS-loopback failure (ordinary selftest
291/1/43) and three raster-rendering failures (Graphics Gallery 29/3/0).
With identical SDK/APKs, Emulator 32.1.11 passed the 25 strict checks,
ordinary selftest 292/0/43 and Graphics Gallery 32/0/0, followed by the complete
suite above. No application test, TLS requirement or SDK optimization was
removed to obtain these results. The exact legacy emulation defect was not
isolated to an instruction; the tested replacement is pinned for x86_64 only.

The API21 runner also needed to distinguish repeated launches of the same
package: retained system-buffer records could describe an earlier process's
normal exit. It now clears all log buffers and binds early process-death
checks to the actual current PID from `ps`. Evidence in `sdk-suite-4` contains
the prior PID 2649 and current PID 2788 while the current native selftest exits 0
with 292/0/43. Fatal-error, native-result and complete-report checks remain.
Unknown case names are rejected before media fetching or guest startup.

Final cleanup bounds adb log capture/console shutdown, verifies the owned
frontend and child command lines, and waits for the owned QEMU child to stop.
A failure-path fixture passed hung-client timeouts, forced parent/child exit,
a child left after its frontend exited, and refusal of an unrelated PID.
The forced case completed within its bound; an unrelated control survived.

## Existing profile regression

The changed selector fetched the original ARM inputs from cache: ARMv7 r04
with Tools 24.4.1 and ARM64 r04 with Tools 25.2.5. Lightweight fixtures verify
SDK/test fetch isolation, ABI-specific SDK reuse/rejection and packaging of
all eight x86_64 deployments, including the separately pinned Emulator 32.
Python/PowerShell syntax and phase-routing checks passed.

The ready Qt 6 ARM64 SDK `sha256:714aa397f8675792ad76de42a06b7da6bee50d7afad5c5218b664af639fcc4e1`
was exercised through the changed shared runner/starter. Run
`x86-64-starter-regression` passed strict C++23 **25/0/0** and QML GUI
**3/0/0**, with current APK hashes checked. This is a focused runner regression;
the original ARM64 full-SDK results remain in its own report.

The same runner also exercised the ready Qt 5 ARM64 SDK in
`qt6-x86-64-runner-regression`: extended strict C++23 **25/0/0**, followed by
extended ordinary selftest **106/0/4** using the same APK. Both native exits
and current APK hashes were checked. This covers repeated-package invocation
through the Qt 5 branch of the shared controller.

## Evidence and limits

Evidence is under `artifacts/qt6-android-lollipop-x86_64/`:

- `cxx23-probe-1/`, the standalone 25-check probe and guest metadata;
- SDK inventory, compiler/qmake queries, API21 ELF report and input provenance;
- `deployment/`, `apk/packages.json`, `apk-architecture-final.json`;
- `sdk-suite-4/`, `final-results.json` and `final-results-table.md`;
- `screenshots-checked.json`, Widgets contact sheet and QML GUI capture.

The Widgets and QML PNGs were visually checked: rendered pages, text and
controls are present. Earlier failed comparisons remain local evidence.

The shared C++ application sources and old-standard guards are unchanged.
C++17 builds the SDK; clients use C++23 plus `-fexperimental-library`.
QtWebEngine, Wayland, Vulkan, DBus, glib and ICU remain outside this profile.
Physical cameras/audio/Bluetooth/NFC/XR and files above 2 GiB were not validated.
Builds and guests ran sequentially. No local security test suites, push or
new tag were invoked.
