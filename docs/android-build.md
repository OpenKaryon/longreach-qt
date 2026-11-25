# Android through make and build-all

Each installed Android SDK has two make targets: the SDK itself and
`-examples`, which builds applications with a ready SDK and packages APKs.
Execution currently requires Windows, PowerShell 7, Python 3.11+, GNU make
and Docker with BuildKit. Set `ANDROID_HOME`, or pass
`ANDROID_SDK="C:/path/to/Android SDK"`. Packaging also needs the host JDK and
Android Build Tools described in the target guides.

`make help`, `make -n` and `build-all.py --list` do not build anything and
work without Android tools.

## Target matrix

| Qt | make architecture | Android ABI | API |
| --- | --- | --- | --- |
| 4 | `arm` | `armeabi` | 4 |
| 4 | `i386` | `x86` | 10 |
| 4 | `amd64` | `x86_64` | 21 |
| 4 | `arm64` | `arm64-v8a` | 21 |
| 5 | `armv7` | `armeabi-v7a` | 10 |
| 5 | `i386` | `x86` | 10 |
| 5 | `amd64` | `x86_64` | 21 |
| 5 | `arm64` | `arm64-v8a` | 21 |
| 6 | `armv7` | `armeabi-v7a` | 21 |
| 6 | `i386` | `x86` | 21 |
| 6 | `amd64` | `x86_64` | 21 |
| 6 | `arm64` | `arm64-v8a` | 21 |

Use these architecture names in make and build-all. ABI spellings belong
to the existing PowerShell `-Abi` parameter; they do not create make aliases.
The registry is `scripts/build/android_targets.py`.

```sh
make qt4-android-arm64                  # SDK only
make qt4-android-arm64-examples         # applications and ready APKs
```

Android has no `build-...`, `-package` or `-test` make aliases. Unlike
desktop examples, Android `-examples` requires a ready SDK and never builds
it implicitly. It runs the existing native examples phase, then packaging;
a failed native phase stops before packaging, and a packaging failure
fails the target. Existing generation, ABI and provenance checks remain.
It never launches an emulator.

Qt 6 SDK mode prepares its default native Linux host SDK using the existing
incremental make target. Selecting `ANDROID_HOST_IMAGE` requires that custom
host image to exist already. Examples mode never prepares a host SDK.
Direct PowerShell SDK mode retains its existing ready-host requirement.

Qt 4 API4 uses the configured static/raster installed SDK described in its
[target guide](targets/qt4-android-donut.md), including its explicit module and
resident-JNI limits. Prepare the pinned API4 input directory as that guide
requires; `ANDROID_INPUT` can select it for either SDK or examples mode.
`qt4-android-arm` uses image `longreach-qt4-android-donut-armeabi:llvm21` and
`artifacts/qt4-android-donut-sdk`, preserving the producer's existing defaults.

The original Qt 4 API4/`armeabi` recipe remains available separately as
`make qt4-android-arm-legacy`. It builds native probes and packages APKs
together, using the original downloaded inputs. It is not an installed SDK
and stays outside build-all; see its [own guide](targets/qt4-android-donut.md).

## Reusing native outputs and running APKs

The existing `scripts/build/qt<N>-android.ps1` interfaces remain available
for the individual `sdk`, `examples` (native-only), `package` and `test`
modes. For example, package already-built Qt 4 ARM64 applications without
recompiling them:

```powershell
./scripts/build/qt4-android.ps1 -Abi arm64-v8a -Mode package
```

Run saved APKs through the existing runners, independently of make:

```powershell
./scripts/run/qt4-android-api21-suite.ps1 -Abi arm64-v8a -RunName arm64-run-1
./scripts/run/qt5-android-suite.ps1 -Abi x86 -RunName intel-run-1 -Emulator 'C:/path/to/ready/emulator-x86.exe'
./scripts/run/qt6-android-suite.ps1 -Abi x86_64 -RunName intel-run-1
```

Runners accept Android ABI names from the table. Pass `-OutputDirectory`
when using a custom application output directory. Qt 4 uses `-Profiles`
for subsets; Qt 5/6 case selection and renderer diagnostics depend on the
selected runner/profile, as documented in the target guides. Subsets do
not qualify a complete suite. Use a new `-RunName` to preserve old evidence.

The recorded Qt 5 API10 x86 14/14 result used an already corrected classic
emulator. Select that existing executable with the runner's `-Emulator`
option to repeat that setup; it does not qualify the affected stock emulator.
No make target builds or patches an emulator.

## Batch builds

```sh
make build-all BUILD_ALL_ARGS="--only qt4-android-arm64"
make build-all-examples BUILD_ALL_ARGS="--only *-android-*"
python scripts/build/build-all.py --list --only '*-android-i386'
```

`build-all` includes the twelve installed-SDK profiles. `--only` and `--skip`
match their canonical names. SDK-only mode invokes each bare SDK target;
batch examples explicitly schedule SDK then `-examples`, producing APKs.
A failed step fails that target. Guests are never launched. Logs and
summaries use the existing `artifacts/qt<N>-android-.../` output directories.
Image tags, installed prefixes and previous result records are unchanged.

Android jobs run alone even with `--jobs` / `BUILD_ALL_JOBS` greater than
one, protecting shared host tools; desktop parallelism is retained.
Standalone make commands participate in the machine build lock, in addition
to the Android artifact locks. Stop an emulator before compiling.

On non-Windows hosts, execution skips Android with an explanation; selecting
only Android fails before provisioning. Listing still shows all profiles.
Android currently supports only `LICENSE_PROFILE=gpl-enabled`; direct
targets reject other profiles and build-all excludes them with an explanation.
Qt versions remain pinned to their existing patch series.

## Make settings

| Variable | Meaning |
| --- | --- |
| `POWERSHELL` | PowerShell 7 executable; default `pwsh`. Paths with spaces are supported. |
| `ANDROID_SDK` | Host Android SDK; defaults to `ANDROID_HOME`. |
| `ANDROID_PARALLEL_JOBS` | Android compiler jobs; default 2 for the existing two-CPU / 3-GiB containers. Batch CLI: `--android-make-jobs`. |
| `NO_CACHE=1` | Disable reusable Docker image layers in SDK mode, including shared tools. BuildKit cache mounts retain source/object caches. Explicit SDK mode always invokes Docker, including with `FORCE=1`. |
| `DOCKER_BUILD_FLAGS` | Extra SDK Docker arguments, parsed as shell words and forwarded as an array. |
| `ANDROID_OUTPUT` | Override the existing output directory for an individual invocation; both native and APK stages use it. |
| `ANDROID_SDK_IMAGE` | Select a ready SDK in examples mode, or its output tag in SDK mode. |
| `ANDROID_HOST_IMAGE` | Custom ready host SDK for Qt 6 SDK mode; suppresses default host preparation. |
| `ANDROID_INPUT` | Pinned API4 inputs for installed SDK/examples or the original legacy recipe. |

Output/image overrides are for one profile at a time; do not point several
batch profiles at the same output or SDK tag. Runner options are passed
directly to runners, without additional make variables. The API4 legacy
recipe does not accept SDK build overrides.

## Tooling checks

`scripts/tests/android/test_android_make.py` checks the two-target contract, absence
of aliases, unchanged SDK identities, batch ordering, host prerequisites,
argument preservation, native-to-APK ordering and failure propagation.
It uses read-only make queries and disposable PowerShell recording fixtures.
The Qt 4/5/6 mode fixtures continue to cover the individual script phases.
No SDK build, Docker run, download, guest, security suite or repository
scanner is required by these ordinary tooling checks.

The `Repository checks` GitHub Actions workflow runs functional tooling
checks on pushes and pull requests, including Android Python discovery,
PowerShell fixtures and the host x86 futex probe. Changes to scripts,
patches and Dockerfiles should use this workflow without `[skip ci]`.
The same automatic workflow checks tracked files for accidental developer
paths, private keys and other leaks, and verifies SPDX headers. These
standard publication checks stay enabled on pushes and pull requests.


## Retained Android build caches

`NO_CACHE=1` rebuilds image layers; it does not clear BuildKit cache mounts.
Qt4 retains source/object caches separately. A new source recipe refreshes its
owned inputs; an unmanifested legacy tree is archived intact beside the new
tree before migration. Old temporary source directories and historical APKs
are preserved. New preparation stages live outside the persistent cache mount.

For an intentional cold rebuild, use a separate Docker builder/cache namespace
and output directory. Keep the existing builder and its caches for recovery;
pruning cache mounts is a separate destructive maintenance operation.
Compiler job counts are supplied through an optional BuildKit secret, default 2,
and are not persisted in SDK image ENV or its cache key. Examples still receive
`PARALLEL_JOBS` as a container execution option.

Docker provenance attestations can still create a different manifest/index ID
on a cache hit even when runtime layers and configuration are identical. The
job-count change fixes compiler-layer invalidation; it does not promise that
attestation-bearing image IDs are stable across separate build invocations.
