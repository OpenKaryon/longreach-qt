# Qt 5 Android API 21 x86_64 with LLVM 21.1.8

Build and final emulator validation completed 2026-11-20 UTC. The full
Qt 5.15.19 SDK, eight shared applications and the extended selftest passed
all thirteen Android 5.0.2/API 21 cases. Both installed-SDK C++23 profiles
passed **25 PASS, 0 FAIL, 0 SKIP**. Ordinary module/API SKIPs remain visible.
These are source recipes and local test artifacts, not published SDK images.

## Toolchain and SDK

ABI `x86_64`, compiler target `x86_64-linux-android21`, explicit CPU baseline
`-march=x86-64-v2`. Upstream LLVM 21.1.8 builds libc++, libc++abi, libunwind
and compiler-rt; NDK r27 supplies platform headers, CRT, link stubs and helper
sources. Its compiler and stock C++ runtime are not used. Qt source builds
use C++17, with QtScript's upstream C++14 setting. Shared application clients
use C++23 with `-fexperimental-library` and one shared C++ runtime.

The existing Qt 5 Android Dockerfile selects ARMv7/API 10 or ARM64/x86_64
API 21. A common API 21 SDK stage installs the runtime, OpenSSL and correct
ABI/API labels. The original ARMv7/API 10 default remains intact. Fetch,
SDK, example, APK and emulator entry points accept the new ABI; examples
consume an inspected immutable SDK image without rebuilding Qt.

Final SDK: `longreach-qt5-android-lollipop-x86_64:llvm21`.
Immutable identity:
`sha256:c030f963961b806d69a9ab695210608da21db99632e2a66e4ea8658687a6377c`.
Installed prefix: `/opt/qt5-android-x86_64-llvm`.
The example build records exactly the same image identity.

The SDK contains **67 Qt module libraries and 199 x86_64 ELF64 libraries**.
The logical module set exactly matches the complete ARM64 profile. Qmake
reports 5.15.19 and the selected prefix. The producer verifies Clang 21.1.8,
SysV hashes, no native ELF TLS and no unsupported newer relocations. Input
provenance records 28 platform/CPU inputs and 1569 effective headers.
QtWebEngine is excluded.

The Qt archive is SHA256
`173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae`.
The 56-patch source fingerprint is
`99015587bd63da36d0e0efdfc67188f966fde88be74ffa706268240a0b348a19`.
The existing Qt 5 lock also pins LLVM 21.1.8 and OpenSSL 3.5.7.
OpenSSL uses the existing Qt 5 Android C implementation configuration.

Runtime image: `longreach-qt5-android-lollipop-x86_64:runtime`, identity
`sha256:94ee7618293868339c2b9445ea2b386e6b8dd155a18d0e0674c3ede18fafdc48`.
Runtime SHA256:
`8b03afda56a3f0bc3fc0309b4edb1f5b08ee29b77d68fe5a1a03393d60563dc0`.
It matches the independently tested probe and the Qt 6 x86_64 runtime.
Qt 5 metadata selects its own SDK prefix without changing runtime ABI/code.

## Guest and standalone C++23

The pinned guest is Android 5.0.2/LSY66K, `x86_64-21_r05.zip`, SHA256
`b652297c0733cced8e9507e5018d78f56b87141c47e4d7ada60f495469f76d49`.
The pinned official Emulator 32.1.11/build 9536276 archive has SHA256
`7720a38136399a93af4a3da57715d69f26d7b86c74d60ea016162e11f1fae439`.
Both inputs reuse the shared API 21 lock and verified Qt 6 emulator setup.
The guest uses kernel-ranchu 3.10, Nehalem CPU emulation with acceleration
off, 1 GiB RAM and SwiftShader GLES. Qt Quick uses its normal GLES backend.
The guest is headless and never captures host input.

The standalone `cxx23-probe-1` passed **25/0/0**, native exit 0, with
Clang 21.1.8, libc++ 210108 and `__cplusplus=202302`. It uses the shared
`moderncpp_checks.h`, covering the required threads, cancellation, atomic
wait, filesystem, unwinding, format/print and expected behavior. This is a
behavior gate, not a claim of exhaustive C++23 conformance.

## Corrections and incremental build evidence

QtDeclarative initially rejected `RegisterID(-1)` as an out-of-range enum
constant expression with Clang 21. The producer now reuses
`patches/qt5/linux-lucid-llvm/01-qml-x86-register-enum.patch`, already used by
Linux, Windows and macOS x86 profiles. It gives the register enum a signed
`int` underlying type. There is no duplicate Android patch, diagnostic
suppression or JIT removal.

The same capped two-CPU/3-GiB offline container retained its source/object
cache. Applying the fix changed one source header; resuming compiled no
QtBase C/C++ sources. QtDeclarative and the remaining SDK then completed.
Production validation/SDK stages packaged the installed SDK without another
source rebuild. All clients, APKs and later tests reused that final image.

`sdk-suite-1` stopped at QML because API 21 logd retained a SIGSEGV from the
already finishing `pm` installation command, PID 3479/Binder_2. This record
preceded the real QML application launch, PID 3536; that app was still
executing its checks. The runner now writes a unique log marker after
install/reset and before each launch. It retains both full and scoped logs;
the collector revalidates the exact boundary against the raw evidence.
All existing fatal/native/Java cleanup checks remain active after the marker,
including system-service failures during the case. Missing/duplicate markers
fail. The marker fixture also checks preservation of current fatal records.

`sdk-suite-2` exposed PowerShell's rejection of empty adb log lines in a
mandatory string-array parameter. The helper now accepts those lines.
The complete final run is `sdk-suite-3`; no SDK or APK rebuild was needed
for either runner correction. Earlier evidence is retained separately.

## Installed-SDK results

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

The collector verifies guest release/API/ABI, native exit 0, captured stdout,
no fatal cleanup error, current APK SHA256, SDK/example image identity and
both strict C++23 gates. All thirteen results passed in one complete run.

Ordinary SKIPs match the ARM64 profile: Qt 6-only APIs and absent platform
modules. OpenGL's six include Qt 6 charts/Qt3D/Graphs interfaces; QML's
thirteen include newer scenegraph/RHI APIs and absent Wayland. The four
extended-selftest SKIPs include unavailable Qt 6/SpatialAudio groups and a
speech group whose backend is exercised by multimedia-lab. No strict C++23
check is skipped.

Widgets and QML PNGs were visually inspected: pages, controls, text and
rendered content are present. Evidence:

- `sdk-suite-3/widgets-gui/files/widgets-gallery-pages.png` (1600 x 1280), SHA256
  `2ba064562d765aed068dda8065bd9e47e87a06ef00533b9c55e6d3f01ee617ef`.
- `sdk-suite-3/qml-gui/files/quick-gallery.png` (800 x 455), SHA256
  `e9a3faf063d00583fa0aa036a62a324dfbe5fb9be82b042437a7c7c20dbe6c95`.

## Tested packages

Every packaged DSO is ELF64/machine 62 under `lib/x86_64/`. All nine APKs
contain the exact standalone-probe C++ runtime above. The artifact verifier
also matched all current package-manifest SHA256 values and SDK identities.

| APK | Native libraries | SHA256 |
| --- | ---: | --- |
| `apk/qt-selftest.apk` | 62 | `5efbdeb79f42ecf382db056f4fc2f01c12052d6e206d65b7a5bc57239535c702` |
| `apk/widgets-gallery.apk` | 25 | `0d6f167abfb7c61ee4bbb6d5b7d3d6b2593f2d9c9e8ade17e63d2632dea25bd1` |
| `apk/graphics-gallery.apk` | 18 | `95eaad44e94b7ebcac36adc2e0b9f8baf990cade69211a6d759b861f7e81c7fb` |
| `apk/painting-lab.apk` | 19 | `1626bc60c35e6ad9451164675b63daaa42b4245c2cea5e98f08d0fd7d0c34b9b` |
| `apk/multimedia-lab.apk` | 25 | `2b744d1b193fae0a9e8c8478e49603e95128c38cd81f23f156cb9dfcd29ec422` |
| `apk/gl-heavy-gallery.apk` | 51 | `c5a218ba15ca0f12f8df8fd4fa258bda93ea0c5633113746dc427b4a3f822e8b` |
| `apk/quick-qml-gallery.apk` | 63 | `efed77a0161ab87cad2ee449c42283ea42c2992a9c6220277c9a7938ac916f12` |
| `apk/network-gui.apk` | 18 | `03f683aede5ea72230d0a9afcdb27188bd12a76ffc454ec2074bef689c977d7f` |
| `apk/extended/qt-selftest.apk` | 66 | `ce07d256ecac108ff11433995bff7403f13b6b6beaafb5fa28dbe9373621b376` |

## Regression and limits

The Qt 5 mode fixture passed ready-image reuse, ABI rejection, SDK-only fetch
scope, all nine deployments for all three ABIs and extended-case routing.
PowerShell/Python syntax, shell line endings and `git diff --check` passed.
The API 10 test fetch still verifies only its original Gingerbread inputs;
x86_64 test fetch verifies only the pinned API 21 guest/emulator inputs.

The ready Qt 6 ARM64 SDK
`sha256:714aa397f8675792ad76de42a06b7da6bee50d7afad5c5218b664af639fcc4e1`
passed the focused `qt5-x86-64-log-boundary-regression`: strict C++23
**25/0/0**, then QML GUI **3/0/0**. Both current APK hashes, native exits and
raw/scoped log boundaries were verified. No SDK or client rebuild was used.

Artifact root: `artifacts/qt5-android-lollipop-x86_64/`. It contains SDK
inventories/provenance/patch state, raw C++23 probe, deployments, APK manifest,
`apk-architecture-final.json`, `final-results.json`, result table, per-case
raw/scoped logcat and `screenshots-checked.json`.

Application sources and old-standard C++ guards remain shared. Physical
cameras, audio devices, Bluetooth/NFC, files above 2 GiB and newer Android
versions were not validated. All builds and guests ran sequentially in the
primary checkout; no worktree, local security suite, push or new tag was used.
