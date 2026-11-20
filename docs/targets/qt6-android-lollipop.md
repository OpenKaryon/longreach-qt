# Qt 6.8.5 for Android API 21

This experimental recipe selects ARMv7 `armeabi-v7a`, ARM64 `arm64-v8a`
or `x86`/`x86_64` from Android 5/API21. ARMv7 remains the default. All four profiles have
SDK and example runtime evidence, including strict C++23 25/25 without SKIP.
The [ARM64 report](../results/qt6-android-lollipop-arm64-v8a-llvm21-20261119.md)
records all eleven installed-SDK cases. The [x86_64 report](../results/qt6-android-lollipop-x86_64-llvm21-20261120.md)
records all eleven installed-SDK cases, both gallery GUI captures and strict
C++23 25/25 without SKIP. The [x86 report](../results/qt6-android-lollipop-x86-llvm21-20261120.md)
records all eleven cases, CPU evidence without SSE4/AVX and the single-core guest workaround.
Qt and applications use upstream LLVM 21.1.8 and one shared libc++ built
from the matching LLVM sources. NDK r27 supplies platform headers, CRT,
link stubs and Android helper sources; its compiler and libc++ are not used.
Runtime verification uses the archived Android 5.0.2/LSY66K API21 image.

## Build and run

On Windows, install Docker Desktop, Python 3.11+, PowerShell 7, JDK17 or JDK21 with
`javac`/`keytool`, and Android SDK platform 35, Build Tools 36.0.0 and Platform
Tools. Select the Android SDK through `ANDROID_HOME` or `-AndroidSdk`.
The entry point has four independent modes. Its default is `examples`, which
uses a ready SDK image and never builds Qt. Select `sdk` explicitly to build
the SDK; missing images produce an error instead of an automatic rebuild.

```powershell
$abi = 'armeabi-v7a' # Or arm64-v8a / x86 / x86_64.

# Build Qt only when necessary (native host tools: make qt6-linux-amd64 first).
./scripts/build/qt6-android.ps1 -Abi $abi -Mode sdk -AndroidSdk $env:ANDROID_HOME

# Compile and deploy the eight shared examples with the existing SDK image.
./scripts/build/qt6-android.ps1 -Abi $abi -Mode examples

# Package the saved deployments; Docker and a compiler are not needed.
./scripts/build/qt6-android.ps1 -Abi $abi -Mode package -AndroidSdk $env:ANDROID_HOME

# Test the saved APKs; no compilation or packaging is performed.
./scripts/build/qt6-android.ps1 -Abi $abi -Mode test -AndroidSdk $env:ANDROID_HOME -RunName sdk-suite-1
```

| Mode | Inputs/actions | Output |
| --- | --- | --- |
| `sdk` | Fetch SDK inputs; build the Docker SDK image | SDK image and `sdk-image-id.txt` |
| `examples` (default) | Inspect an existing SDK; compile/deploy shared C++23 sources | `deployment/`, Java/runtime packaging inputs, `examples-sdk-image-id.txt` |
| `package` | Read existing deployments and Java/runtime files; run host APK tools | `apk/` and APK hashes |
| `test` | Read existing APKs; prepare emulator media; run the serial suite | Fresh run directory and reports |

`-SdkImage` selects the output image tag for `sdk`; `examples` accepts an
existing tag or immutable image ID.
The example mode validates the platform/version/compiler labels and runs the
inspected immutable image ID. It needs Docker, but no host Android SDK,
JDK, source archives or host Qt image. It never downloads inputs, builds an
image, packages APKs or starts an emulator.

The package/test modes need the existing output directory and appropriate
host Android tools. Packaging needs platform35, Build Tools36.0.0 and JDK17/21;
testing needs adb and the pinned emulator media. Test preparation fetches only
the emulator/system-image archives, without reading or downloading LLVM, Qt,
OpenSSL, NDK or Java compile inputs. The standalone runner remains available
as `scripts/run/qt6-android-suite.ps1`.

For `sdk`, `-HostImage` selects an already built Qt 6.8.5 host image; its default
is `qt6-linux-amd64-llvm21:latest`. The legacy `-SdkOnly` switch remains an
alias for `-Mode sdk` and cannot be combined with another explicit mode.
The old implicit SDK → examples → APK chain is replaced by the explicit
commands above. The build-input hashes are unchanged in
`scripts/fetch/locks/qt6-android-api21-inputs.json`.

Choose the smallest phase needed by an edit:

- Qt/runtime/toolchain changes: `sdk`, then `examples`, `package`, `test`.
- Shared C++ example changes: `examples`, then `package`, `test`.
- APK packaging or the thin Java Activity: `package`, then `test`.
- Runner changes: `test`; documentation changes need no native build.

The example mode deliberately uses the selected ready image; it does not
check Qt patch freshness or rebuild the image to match the working tree.
Its recorded image ID identifies the SDK used for those example binaries.

For lightweight orchestration regression checks:

```powershell
./scripts/tests/test-qt6-android-modes.ps1
```

These checks use disposable fixtures and recording stubs for Docker,
downloads, APK tools and the emulator. They do not compile or start a guest.

The ARMv7 image is `longreach-qt6-android-lollipop:llvm21`, with prefix
`/opt/qt6-android-armeabi-v7a-llvm`. ARM64 selects
`longreach-qt6-android-lollipop-arm64-v8a:llvm21`, with prefix
`/opt/qt6-android-arm64-v8a-llvm`. The x86 tag is
`longreach-qt6-android-lollipop-x86:llvm21`, with prefix
`/opt/qt6-android-x86-llvm`. The x86_64 tag is
`longreach-qt6-android-lollipop-x86_64:llvm21`, with prefix
`/opt/qt6-android-x86_64-llvm`. All use the external CMake toolchain at
`/opt/longreach-android-api21/toolchain.cmake`. The final image includes the
compiler, runtime, host tools, target SDK, OpenSSL and Android build inputs.
The runtime, OpenSSL and Qt compilation stages run without network access.
Only provisioning the shared tools stage and fetching pinned inputs need it.
Only Dockerfile lives in `docker/qt6/android/`; helpers are under `scripts/`.

ARMv7 outputs default to `artifacts/qt6-android-lollipop/`; ARM64 defaults to
`artifacts/qt6-android-lollipop-arm64-v8a/`; x86 defaults to
`artifacts/qt6-android-lollipop-x86/`; x86_64 defaults to
`artifacts/qt6-android-lollipop-x86_64/`. Pass `-OutputDirectory`
to both wrappers to select another location. `deployment/` holds Qt-generated
dependency/QML staging; `sdk-packaging/` holds Java packaging files; `apk/`
contains locally signed v1 APKs and their SHA256 manifest. Packaging compiles
Java against API35 and uses minimum/target SDK21 for these legacy examples.
The certificates are development-only. Compiler/runtime provenance, module inventory, qmake
queries and API21 ELF-loader checks are exported alongside them.

The suite creates a fresh task-owned headless emulator, runs strict C++23
first, all eight ordinary examples, then Widgets and QML gallery rendering.
All 25 strict checks must pass with zero FAIL/SKIP. Ordinary hardware/platform
SKIPs remain explicit. The complete eleven-case report checks guest version,
native exit status, fatal cleanup errors and current APK hashes. Reports and
screenshots are pulled before successful APKs are uninstalled to free guest
space. A partial `-CaseNames` diagnostic never produces a complete-suite report.

Builds use two compiler jobs and one link job; example compilation is capped
at 2 CPUs / 3 GiB. Stop any existing Android emulator before compiling. Run only one
SDK build or emulator at a time. Run directories must have unique names;
the runner refuses to overwrite prior evidence. No keyboard/mouse capture is
used. ARMv7 uses pinned Windows SDK Tools 24; ARM64 uses Tools 25.2.5 with
the image's ARM64 `kernel-qemu` 3.10 and a run-owned QEMU2 AVD. x86_64 uses
Emulator 32.1.11 (build9536276), its image's `kernel-ranchu` 3.10, a Nehalem
CPU model and software CPU emulation with two guest cores. Both legacy GPU
options (`on`/`mesa`) select SwiftShader GLES for this headless x86_64 profile;
Qt Quick still uses its normal GLES backend. Vulkan and file-backed quickboot
are disabled. The selected emulator archive has an official SHA256 pin.
The x86 profile uses the same pinned emulator and software GLES with a Conroe
CPU model and one guest core. Its SSSE3 baseline needs no SSE4 or AVX. The
archived 32-bit kernel panicked during a normal two-core TCG boot; the tested
profile uses one core without disabling native threads. Boot queries have
individual/overall deadlines and detect recorded kernel panics.
No HAX installation is required. The x86_64 compiler baseline is Android's x86-64-v2 instruction set; AVX is not required.
The fetcher selects the requested ABI's pinned revision (ARM r04, Intel r05)
and emulator archive for tests. Default rendering is GLES, with no forced
Qt Quick software backend.

## Boundaries

QtWebEngine, Wayland, Vulkan, DBus, glib and ICU are excluded. Native Android
multimedia, OpenSLES, TextToSpeech and WebView are built. The Qt6 Android API21
patches guard newer Java APIs at runtime and retain modern paths on newer
systems. Shared memory and system semaphores unavailable in this profile are
guarded in the common examples. C++17 builds the SDK; example clients require
C++23 plus `-fexperimental-library`, including jthread/stop_token behavior.
This is behavior coverage, not full standard-library conformance.

Large files above 2 GiB with this pre-API24 stdio profile, physical device
cameras/audio/Bluetooth/NFC/XR were not validated. Intel validation is tracked
separately in the x86 and x86_64 result reports.
API21/22 long bundled-library paths use a basename retry after
the original load fails, preserving the application native-library search path.
This target uses QtActivity and shared Qt libraries; applications
must preserve applicable Qt/libc++/platform licences when distributed.

See the [build and emulator evidence](../results/qt6-android-lollipop-armeabi-v7a-llvm21-20261118.md).


## Shared compiler inputs

Android host tools build from the digest-pinned Ubuntu 22.04 image and the
project's dated apt snapshot. Clang/LLD 21.1.8 come from the SHA256-pinned
upstream LLVM source archive, with X86, ARM and AArch64 backends. The host
compiler builds with two jobs and one link job. The shared image is refreshed
through Docker's cache whenever SDK mode is requested; a pre-existing tag is
not a freshness check. Build its Dockerfile with the repository root as context.

These producer inputs describe the current recipe. Earlier result reports
identify the SDKs actually tested; changing the compiler recipe does not
retroactively qualify an older image as a fresh build from the new producer.

## Completed example generations

Examples mode marks the output incomplete before changing any deployment,
Java input or runtime. Only a successful complete build writes
`examples-manifest.json`, recording the selected immutable SDK ID, ABI and
hashes of every packaging input. Packaging checks those files before changing
any APK and writes `apk-manifest.json` only after all APKs finish. Test mode
requires the completed APK generation and verifies its hashes before booting.
Qt 5 includes both core and extended selftest deployments.

A failed rebuild leaves earlier APKs on disk for inspection, but they cannot
be packaged or tested as the new generation. Complete examples mode, then
package mode, before starting the new test run. Existing outputs without
these manifests need that explicit refresh; the scripts do not silently adopt
them or rebuild the SDK. Saved APK test mode needs the manifests and image-ID
files, but it does not require the SDK or deployment directories.

PowerShell 7 is required for the Windows entry points. Ordinary artifact
regressions are `scripts/tests/test_android_artifacts.py` and
`scripts/tests/test-android-generation.ps1`; they need no SDK build or guest.

The [Android audit follow-up](../results/android-audit-fixes-20261120.md)
records the current generation checks and installed-APK consumer validation,
with exact SDK identities and retained failures. Native SDK provenance stays
separate from consumer refreshes.
