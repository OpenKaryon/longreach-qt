# Qt 5 Android API 21 ARM64 with LLVM 21.1.8

Build started 2026-11-19 UTC; final emulator validation completed 2026-11-20 UTC.
The full Qt 5.15.19 SDK, eight shared applications and the extended selftest
passed all thirteen required Android 5.0.2/API 21 cases. Both installed-SDK
C++23 runs passed **25 PASS, 0 FAIL, 0 SKIP**. Ordinary platform/module SKIPs
remain visible below. These are source recipes and local test artifacts;
SDK images, guest media and local development signing keys are not releases.

## Toolchain and inputs

ABI `arm64-v8a`, target `aarch64-linux-android21`. Upstream LLVM 21.1.8 builds
libc++, libc++abi, libunwind and compiler-rt. NDK r27 supplies platform headers,
CRT, link stubs and helper sources; its compiler and stock libc++ are not used.
Qt and clients share one C++ runtime. Qt source compilation uses C++17
(QtScript retains its upstream C++14 setting); strict clients use C++23 and
`-fexperimental-library`.

The Qt archive, LLVM and OpenSSL are pinned by the Qt 5 Android input lock.
Platform/emulator inputs reuse the API 21 lock and producer helpers introduced
for Qt 6, with no Qt 6 target SDK/image dependency. The existing Qt 5 Dockerfile
selects ARMv7/API 10 or ARM64/API 21. Compiler/CMake metadata captures the ABI,
API and Qt-generation-specific prefix. The original ARMv7 profile remains
the default, including its own OpenSSL API 10 installation.

The pinned ARM64 emulator image is Android 5.0.2/LSY66K:
`arm64-v8a-21_r04.zip`, SHA256
`6f9f8ab64641ccbea92a02cc85c130a60c3464b87aa9d49952a8d8292f84d073`.
SDK Tools 25.2.5 SHA256 is
`da1a0bd9bb358cb52a8fc0a553a060428efe11151e69b9ea7a5cbacb27cf1c7c`.
The guest uses the archive's 3.10 `kernel-qemu`, a ranchu kernel for ARM64,
with a task-owned headless AVD, 1 GiB RAM and GLES. The suite starts one guest
and stops it in `finally`; no host keyboard or mouse capture is used.

## SDK and standalone C++23

The standalone `cxx23-probe-1` passed **25/0/0**, native exit 0, using the same
`moderncpp_checks.h` as the shared examples. This covers the required thread,
cancellation, atomic wait, filesystem, unwinding, format/print and expected
behaviors; it does not claim exhaustive C++23 conformance.

The full SDK contains **67 Qt module libraries and 199 AArch64 ELF64 libraries**.
The producer verifies qmake 5.15.19, SDK prefix, Clang 21.1.8, SysV hashes,
no native ELF TLS and no newer packed relocations. QtWebEngine is excluded.

Final SDK image: `longreach-qt5-android-lollipop-arm64-v8a:llvm21`.
Immutable Docker identity:
`sha256:e2e835b2824adc1c97e2b0d7cced5da55f3294db72b9ecdf7abedc68ba6d2747`.
Installed prefix: `/opt/qt5-android-arm64-v8a-llvm`.
The example build records the same immutable image identity.

Runtime SHA256, identical to the separately tested standalone runtime:
`fa08e29dc1ee5cb12af97b2ca60b25c1b15dd8d198ab7dd648d48395f78e69db`.
The final source stack contains 56 patches; fingerprint:
`e51fbce1185ece0ff4d1a7eef3d7c9625870754cc5e01fba8b9f563b8a4351f6`.
Producer evidence under `artifacts/qt5-android-lollipop-arm64-v8a/` includes
`sdk-modules.txt`, `sdk-api21-elf.json`, `platform-input-provenance.json`,
`runtime-sha256.txt`, `sdk-qmake-query.txt` and `qt-patch-state.json`.

All build stages and guests ran sequentially. After integration fixes, a
capped two-CPU/3-GiB task-owned Docker container retained completed objects;
only changed source files were rebuilt. Final SDK validation and export used
the production validation/SDK stages. There was no second Git checkout or
worktree, and no full QtBase/runtime rebuild for later integration fixes.

## Compatibility fixes found by the actual builds and runs

- Clang 21 rejects the ARM64 QML JIT register sentinel outside the inferred
  enum range. The existing Linux ARM64 fixed-underlying-type patch is reused,
  with no duplicate Android patch.
- NDK r27 disallows `ALooper_pollAll`. Sensors uses `ALooper_pollOnce` inside
  the existing five-millisecond event/quit loop. Its declaration and export
  were also checked in the old NDK r7/API 9 ARM inputs used by API 10.
- API 21/22's loader rejects long input names. An existing absolute plugin
  path of at least 128 encoded bytes gets a basename retry in the application
  library search path. QML coverage and dependency deployment remain intact.
- `sdk-suite-1` passed strict C++23 but crashed in QtScript's ordinary
  function-call check. This matches the prior Linux ARM64 LLVM tagged-frame
  issue. Android now reuses
  `patches/qt5/windows-xp-llvm/02-qtscript-host-call-flag.patch`, inspecting the
  raw pointer before dereference. The retry compiled 127 QtScript source
  files while retaining other module objects. The check passes in both later
  runs; it was not removed.
- `sdk-suite-2` passed strict C++23 and the first four ordinary apps, then
  Pico TTS threw `NullPointerException: collection == null` from `getVoices()`.
  The pending exception caused a JNI abort. Patch 26 handles null/throwing
  enumeration and uses the existing language-based voice implementation for
  older engines without the new voice API. Native voice enumeration remains
  active for working modern engines. The final update changed two Speech
  source files and compiled one target C++ source. Multimedia's backend and
  voices check now passes without SKIP.

The two failed runs, stdout and logcat are retained separately. Packaging
archives previous APKs before replacement. The final run is `sdk-suite-3`.

## Installed-SDK emulator results

All eight application sources remain shared with desktop/other targets.
The extended selftest changes its selected groups, not its implementation.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 208 | 0 | 63 |
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

The collector verifies all thirteen cases, captured stdout summaries, native
exit 0, no fatal cleanup error, Android release/API/ABI, SDK/example identity
and each current APK SHA256. It reruns the canonical modern-C++ gate for both
strict profiles. `final-results.json` and `final-results-table.md` bind this
result to the actual packages in `apk/packages.json`.

The ordinary SKIPs describe Qt 6-only APIs and absent platform modules;
OpenGL's six include Qt 6 charts/Qt3D/Graphs APIs, and QML's thirteen include
Qt 6 scenegraph/RHI interfaces and absent Wayland. The extended selftest's
four include three unavailable Qt 6/SpatialAudio groups and a speech group
whose real backend is exercised by multimedia-lab. No C++23 check is skipped.

Widgets and QML PNGs were visually inspected: controls, text, graphics and
page content render correctly. The evidence is:

- `sdk-suite-3/widgets-gui/files/widgets-gallery-pages.png` (1600 x 1280), SHA256
  `942cf5a8f998372849d060b6dd57905019d0fd05ce7249b7ea795abd4b28ab00`.

- `sdk-suite-3/qml-gui/files/quick-gallery.png` (800 x 455), SHA256
  `1a387fa38bd1d546b148f567c1437131191d5eae99e23144bc5b9e3248d749e4`.

## Tested packages

All nine packages contain AArch64 ELF64 DSOs and the exact runtime above.
`apk-architecture.json` records the ELF inventory and runtime hash per APK.

| APK | Native libraries | SHA256 |
| --- | ---: | --- |
| `apk/qt-selftest.apk` | 62 | `2215cb1640d5446ac9fa2dad831531d2492e9ad6e5799ad55672fa311506d2d7` |
| `apk/widgets-gallery.apk` | 25 | `f9a117401c392d75fae8eb78a911630856591f8e51aadbedadaea36592f50759` |
| `apk/graphics-gallery.apk` | 18 | `da6b1b344bb4547554cb879102fa5ce294158ed82cc900d5bddb2b5578a150d7` |
| `apk/painting-lab.apk` | 19 | `489095cdde024e2e01e1bc499ec918038981b4349c6d59e3672a462b01e25388` |
| `apk/multimedia-lab.apk` | 25 | `5437c61f3c010b84c09af2104084eb858c1f23a5b0c93f0a84a0e32b8a77f45a` |
| `apk/gl-heavy-gallery.apk` | 51 | `d94807f2150cf762b4ad5987ae3b1a199578e3227c04a0368ad9e2f6af31f8c0` |
| `apk/quick-qml-gallery.apk` | 63 | `99ebe8f666d648d22d59541241efc23b39bd203d9e81f3ec17203cd02745ac65` |
| `apk/network-gui.apk` | 18 | `53bcae204aac16e67a3dfb6df3e3e76577c7227c4a88d7b2fd0121e43ff740d8` |
| `apk/extended/qt-selftest.apk` | 66 | `7584c886cb0df8cc96226a701e0ab9276a8a7d13a0da17a9e248b1684b20e2d9` |

## Focused regressions and boundaries

The original API 10 ready SDK
`sha256:baa66f218c6c3e3a6121294de3eab10e87b0069cfcc09960329e9a969827ce5c`
built all eight applications plus the extended selftest through the changed
scripts, then packaged all nine APKs. Fresh Android 2.3.3/API 10 ARMv7 runs
passed strict C++23 **25/0/0** and QML GUI **3/0/0**. Evidence stays under
`artifacts/qt5-android-gingerbread/arm64-integration-regression/`. This verifies
client/tool routing with the existing SDK; it does not claim a fresh API 10
SDK source build.

Qt 6 ARM64's existing SDK/APKs also passed strict C++23 **25/0/0** and QML GUI
**3/0/0** through the extracted common runner and its legacy wrapper, under
`artifacts/qt6-android-lollipop-arm64-v8a/qt5-common-runner-regression/`.
No Qt 6 SDK or application recompilation was needed. Partial selection leaves
the original complete eleven-case Qt 6 report unchanged.

Lightweight Qt 5/Qt 6 mode fixtures, Python/PowerShell/Bash syntax checks,
`git diff --check` and the TTS provider boundary fixture have passed. The provider fixture covers native, null, empty and throwing
providers, language fallback, uninitialized state and API 10 avoiding new APIs.

The sdk/examples/package/test modes are independent; default examples reuses
an inspected SDK and cannot implicitly compile one. Packaging validates all
nine deployment trees before replacing output. Partial runner selections are
diagnostic and cannot create a complete final report.

No physical camera, Bluetooth/NFC, sensor, live audio/GPS, production purchase
or audible synthesis validation is claimed. AndroidExtras service/Binder/Intent
coverage remains the previously documented gap. Files above 2 GiB are untested
with this pre-API 24 stdio profile. The emulator validates Android 5.0.2, not
separate physical 5.0.0 devices. No local security tests, push or tag creation.

See [the target guide](../targets/qt5-android-lollipop.md) for exact mode commands.
