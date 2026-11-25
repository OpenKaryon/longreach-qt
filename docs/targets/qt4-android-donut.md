# Experimental Qt 4.8.7 for Android 1.6

The [make interface](../android-build.md) exposes this original combined recipe
as `qt4-android-arm-legacy`. It remains separate from installed-SDK batch targets.

The Android profile builds diagnostic and example APKs for Android 1.6 (API 4,
`armeabi`). The native build runs in a Linux amd64 Docker container with
Clang and LLD 21.1.8. It builds static libc++, libc++abi, libunwind and
compiler-rt against the old Bionic sysroot. Qt uses separate QtCore and
Qt Quick 1 configurations. The latter displays Qt's raster output through
JNI and Android Canvas using the Qt minimal QPA plugin.

The additional [Android 5/API 21 x86_64 profile](qt4-android-lollipop.md)
has separate SDK, examples, packaging and test modes. API 4/armeabi remains
the default of the original build entry point.

## Inputs

On Windows 10 or later, use Docker Desktop with Linux containers, PowerShell 7, a JDK
with `javac` and `keytool`, and the Android SDK with Build Tools 36.0.0 and
Platform Tools. The build/runner metadata and shared C++23 result validator require Python 3.11
or later. This legacy recipe does not require an Android 35 platform JAR.

Stage the Qt and LLVM source archives in `downloads/` using their existing
fetch rules:

```sh
make download-qt4 downloads/llvm-project-21.1.8.src.tar.xz
```

Stage these three archived Android inputs in `downloads/android-donut/`
or pass their directory as `-InputDirectory`.

| Input | Source |
| --- | --- |
| `aosp-ndk-r7-api4-arm.tar.gz` | [AOSP NDK r7 ARM API 4 sysroot archive](https://android.googlesource.com/platform/prebuilt/+archive/968372cd8fffab51ff89c6b3cb40bc74ede24cb9/ndk/android-ndk-r7/platforms/android-4/arch-arm.tar.gz) |
| `android-1.6_r03-linux.zip` | Android 1.6 revision 3 SDK archive containing `android.jar` and the ARM system image |
| `tools_r24.4.1-windows.zip` | Android SDK Tools 24.4.1 for Windows containing `emulator-arm.exe` |

The scripts check the archive hashes against the
[result report](../results/qt4-android-donut-armeabi-llvm21-20261116.md).
The Android SDK used for packaging can be selected with `ANDROID_HOME`
or `-AndroidSdk`.

## Build and run

From the repository root, run the build and emulator in order:

```powershell
./scripts/build/qt4-android.ps1
./scripts/run/qt4-android-donut.ps1
```

Both commands accept `-OutputDirectory`. The default is
`artifacts/qt4-android-donut/`. The build uses two jobs and a 3 GiB memory
limit. The Docker image installs the build tools, and the clean native
build then runs offline from the archives. Packaging uses a disposable
local signing key and v1 APK signing for API 4.

| APK | Check |
| --- | --- |
| `bootstrap.apk` | JNI library loads and returns 42 |
| `strict.apk` | The classic C locale and all 25 shared C++23 checks pass |
| `core.apk` | QtCore 4.8.7 UTF-8 strings and file I/O, application event loop and timer |
| `selftest.apk` | Shared Qt application checks, including files, threads, raster/fonts, XML, TCP/UDP loopback, SQLite and QtScript |
| `quick.apk` | Switch and lifecycle smoke checks, plus Qt Quick Gallery navigation and Widgets Gallery checkbox and tab input |
| `graphics.apk` | Graphics Gallery `--selftest`, including raster effects, widgets and animation |
| `network.apk` | Network GUI `--selftest`, including TCP listen and UDP bind |
| `painting.apk` | Painting Lab `--selftest`, including raster, fonts, SVG and print preview |

The runner boots one emulator per APK, verifies the guest's release, API
and ABI, and saves each attempt under a fresh `run/<profile>-<run-id>/`
directory. Its `run-inputs.json` binds the selected APK, JNI library and the
completed native/APK manifests. These remain resident-JNI diagnostics with
`qualification: false`. A completed diagnostic requires a verified owned
host-tree shutdown, unchanged inputs/reports and successful final log capture.
It does not claim normal Android application-process termination.
Use `-Profiles quick` to rerun both gallery checks. Native libraries,
QtCore's static archive and ELF reports are under `native/`. Qt Quick
Gallery and Widgets Gallery each appear in the Android launcher after
installing `quick.apk`.
See the [example validation report](../results/qt4-android-donut-examples-20261117.md)
for platform limits and guest results.


## Installed SDK producer

The explicit SDK phase exports this same API4/armeabi raster profile:

```powershell
./scripts/build/qt4-android.ps1 -Abi armeabi -Mode sdk -OutputDirectory artifacts/qt4-android-donut-sdk
```

It selects the separate `api4-sdk` Docker stage and image
`longreach-qt4-android-donut-armeabi:llvm21`. The original
`longreach-qt4-android-donut:llvm21` tag remains reserved for shared host tools;
the no-mode combined recipe and `qt4-android-arm-legacy` interface stay intact.
Use a fresh output directory for each SDK generation so failed source captures
and earlier identities remain available. Custom `-InputDirectory` archives are
read through a separate BuildKit context.

The installed prefix `/opt/qt4-android-armeabi-llvm` supplies headers, host
qmake/moc/rcc/uic, eight selected static Qt modules, raster/QML plugins and
independent mkspecs. `/opt/longreach-android-api4` supplies the sysroot, C/C++
drivers, static libc++/ABI/unwind/experimental libraries, compiler-rt builtins
and ARMv5 compatibility/startup objects. The final image contains the installed
prefixes rather than retained source/build trees. This export preserves the
profile's disabled modules; it does not enable desktop Qt4 capabilities on API4.

`sdk-generation.json` binds the immutable image ID, producer payload manifest
and the before/after source/archive capture. Producer recipes must match that
capture; a successful export is not a guest result. The installed verifier is
`/opt/qt4-android-armeabi-llvm/libexec/api4-sdk/api4-sdk.py verify`.
Use the same output directory for the separate consumer phases:

```powershell
./scripts/build/qt4-android.ps1 -Abi armeabi -Mode examples -OutputDirectory artifacts/qt4-android-donut-sdk
./scripts/build/qt4-android.ps1 -Abi armeabi -Mode package -OutputDirectory artifacts/qt4-android-donut-sdk
./scripts/build/qt4-android.ps1 -Abi armeabi -Mode test -OutputDirectory artifacts/qt4-android-donut-sdk
```

`examples` compiles all eight JNI diagnostics from installed headers, libraries
and host tools inside the immutable SDK image. It neither rebuilds Qt nor copies
the producer's clients. Its native receipt binds the SDK generation, payload and
source hashes; `package` and `test` require that binding, preserving the existing
APK/JNI, named coverage and owned-process checks. `test -Profiles core,quick`
selects individual diagnostics; omit `-Profiles` for all eight. API4 uses unique
per-profile attempt directories rather than `-RunName`.

Qualification still requires fresh completed diagnostic receipts. Historical
combined-recipe APKs below do not supply evidence for the installed SDK.

### ARMv5 atomic coverage in the installed SDK strict client

The API4-only strict client calls all eight exported compatibility symbols
directly: barrier,32-bit CAS/add/sub/AND/exchange and8-bit CAS/exchange. Byte
operations check all four byte lanes and preserve neighboring bits. Four
pthreads perform1024 word increments each,then1024 exchanges per byte lane.
The `ARMV5_ATOMIC:` transcript records kernel helper version and ten exact
direct/contended observations alongside the unchanged25C++23 checks.

Installed-SDK diagnostics require both transcripts and retain independent
resident JNI/owned-tree cleanup checks. A nonzero strict JNI result still
saves its report before rejection. Historical combined-recipe receipts keep
their original contract. This probe covers the configured32-bit/8-bit paths
on the recorded guest;64-bit,generic large-object atomics and physical SMP
memory ordering need their own evidence. Component compile/partial-link and
recorded report fixtures are not an Android runtime result.

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


See [Android artifact generations and coverage](android-artifacts.md) for phase
ownership, packaging receipts, ABI preflight, per-target coverage limits and
the private ADB environment used in local reproduction.


## Combined-recipe generations

The producer and runner acquire the same artifact-root OS lease as other Android
targets. A busy root fails before metadata/tool operations; same-process attempts
also refuse an active owned emulator using that root. Native work reserves
`donut-native-in-progress.json`, records the pinned Qt/LLVM/API4 archives and
recipe sources, and writes to a fresh `native-build-<id>` directory. The container
uses its inspected immutable tool-image ID. Completion requires all eight
ARMv5 JNI libraries, ELF reports and the QtCore archive. Promotion retains the
previous native files and completed receipts in `native-history/<id>/`; it does
not fill missing fresh outputs from an old generation or purge history.

`donut-native-manifest.json` describes this combined recipe and its static
runtime, rather than an installed Qt SDK. Packaging initializes/reuses the local
key and resolves one Java toolchain before reserving
`donut-apk-in-progress.json`. `donut-apk-manifest.json` binds the native manifest,
all eight APKs and their exact packaged JNI bytes, API4/armeabi badging, packaging
sources, key bytes and host tools/JDK snapshot. The selected platform JAR must
match the member of the pinned API4 archive; API35 is not substituted.

An interrupted generation remains pending and cannot be tested. Retain its
files, diagnose the failure and explicitly recover before rerunning the combined
recipe. Existing APKs without these receipts remain historical; the runner
refuses them, and no manifest is inferred or backfilled from old output files.
A fresh native build requires separate authorization in the current review.

The runner now uses the shared bounded ADB client, retained Windows job
supervisor and artifact-lease transfer. Quick instrumentation has a 55-second
client budget; final cleanup always stops the owned tree and requires successful
nonempty final log capture. Actual unquoted argv and the current complete
SDK/tool inventory are saved as emulator-launch.json and emulator-media.json.

Selftest and network reports use named coverage policies as well as count
floors. A new SKIP, duplicated outcome or missing required behavior cannot be
hidden by compensating PASS counts. API4 shares the Qt4 lists, with only
`xmlpatterns/xquery-eval` and `xmlpatterns/extras` added for its disabled
QtXmlPatterns module. API10/API21 retain required XQuery coverage. This policy
does not turn an API4 diagnostic into full-suite qualification.

The android-donut-state.py complete/verify commands independently check native/
APK/JNI generation, argv/media, frozen reports, required behaviors, late fatal
logs, final-capture proof and host-tree completion. They take --root and --run,
acquire the root lease and never launch a guest. Qualification remains false.

Ordinary recording checks cover all eight synthetic profiles, focused/retry
paths and 25 injected failures, with no actual device, Docker, JVM or native
program. The producer and runner now prepare both archived inputs through
verified extraction receipts, rather than accepting the original marker files.
Actual native/guest qualification and installed-SDK parity remain unclaimed.

## Prepared API4 media

The PowerShell archive wrapper delegates to prepare-media.py under the same
artifact-root lease. It accepts only the pinned API4 SDK and SDK Tools archives,
checks the archive hash and required layout, and reuses the shared staged ZIP
extractor. A warm tree must match its extraction recipe, exact file inventory
and recorded SHA256s. Missing receipts, old markers and changed/extra files
require staged restoration. The replaced tree and incomplete staging remain
available for diagnosis; no automatic history purge is performed.

Diagnostic media receipts now bind both archive identities, extraction receipt
hashes, extractor/preparer source hashes and the complete current input files.
Completion/reverification require that prepared cache as well as the per-run
snapshot. Native files, APKs, other cache roots and per-attempt writable userdata
are preserved. An active emulator on any supported ABI refuses API4 preparation;
the runner checks this before expanding media.

Six ordinary cache methods exercise tiny ZIPs, warm reuse without extraction,
old-marker recovery, drift repair/history, interrupted staging, wrong/incomplete
archives and standalone lease refusal. The complete producer/runner recording
uses the actual PowerShell archive function and extractor with fixture pins;
all described binaries remain inert data. Real archived media was only inspected
for layout, with no extraction, replacement or execution during this review.
Older diagnostic receipts missing this prepared-cache chain remain historical;
do not backfill them or claim a fresh Android result.
