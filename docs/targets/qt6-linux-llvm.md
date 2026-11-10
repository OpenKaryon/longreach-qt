# Qt 6 Linux amd64 SDK with LLVM 21.1.8

This profile rebuilds static Qt 6.8.5 with upstream Clang/LLD 21.1.8 and
static libc++, libc++abi, libunwind and compiler-rt. It retains the CentOS 7
userland and GLIBC 2.17 floor. The ordinary `qt6-linux-amd64` make target
continues to use GCC; the LLVM SDK uses the separate local image tag
`qt6-linux-amd64:llvm21` and prefix `/opt/qt6-linux-amd64-llvm`.

The shared compiler comes from
[`docker/qt6/host/Dockerfile-llvm`](../../docker/qt6/host/Dockerfile-llvm).
It is upstream LLVM, not LLVM-MinGW. The seed image contains the pinned
CentOS RPM dependencies, patched Qt 6.8.5 source, static OpenSSL and Wayland
dlopen stubs. Those C dependencies are reused; Qt is compiled again with
Clang and libc++. The fixed profile includes the GPL-enabled module set
and excludes Qt WebEngine/WebView, matching the earlier Linux LLVM pilot.

## Pinned inputs

The [probe input record](../../scripts/build/qt6-llvm-probes/inputs.json)
pins LLVM 21.1.8 to SHA256
`4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142`.
Stage the archive at `downloads/llvm-project-21.1.8.src.tar.xz` and prepare
the shared compiler image as described in the
[six-target probe guide](qt6-llvm-probes.md). The current shared compiler
image was built from the locked-RPM GCC seed
`qt6-linux-amd64:centos7-rpm-lock-check`; see its
[RPM build report](../results/qt6-linux-amd64-centos7-rpm-lock-20261104.md).

The toolchain helper builds the native x86_64 LLVM runtimes in two stages:
compiler-rt builtins first, then libunwind/libc++abi/libc++. Linux explicitly
selects libc++abi's existing weak-symbol TLS fallback for glibc 2.17,
avoiding a false-positive compile-only configure check for
`__cxa_thread_atexit_impl`. It installs those runtimes beside the compiler
under `/opt/llvm-21` and verifies the installed wrappers with all 25 required
C++23 checks before building Qt. Consumer wrappers do not reference the
build work volume.

## Sequential build with hard resource limits

From the repository root, with the shared compiler image already available:

```sh
python scripts/build/qt6-linux-amd64/build-sdk.py
```

The coordinator holds the existing SDK build lock and refuses to start a
stage while another container is running. The default sequence builds the
toolchain, builds Qt, then runs the required SDK checks. It uses one container at a time,
four CPUs, an 8 GiB memory limit and no network. Ninja gets four compile
jobs and a single link pool. The compiler bootstrap is reused; the native
runtimes and Qt are built by the same helpers used in `Dockerfile-llvm`.

The toolchain stage saves `qt6-linux-amd64:llvm21-toolchain`; the Qt stage
saves `qt6-linux-amd64:llvm21`. Image commits preserve the installed files
and compiler environment, with no dependency on host bind mounts or work
volumes. Build containers are retained, and the Qt object volume
`longreach-qt6-linux-amd64-llvm21-build` allows an interrupted build to be
continued. The shared compiler/probe volume is
`longreach-llvm21-probes-build`. No cache or old image is pruned.

Build logs are `build/qt6-linux-amd64-llvm21-{toolchain,qt}.log`; per-stage
JSON records and probe output are in
`artifacts/tests-qt6-linux-amd64-llvm21/`. The installed SDK includes its
Qt configure summary and CMake cache under `share/longreach/`.

If a stage fails, inspect its log and stopped container before retrying.
After removing only that stopped build container, `--stage toolchain` or
`--stage qt` reruns the selected stage with its existing object volume.
Other containers, images and volumes should be preserved.

The equivalent Dockerfile recipe remains available for builders that
already enforce their own resource limits:

```sh
docker build --network=none --progress=plain \
  --build-arg PARALLEL_JOBS=4 --target qt \
  -f docker/qt6/linux/amd64/Dockerfile-llvm \
  -t qt6-linux-amd64:llvm21 .
```

Its BuildKit caches are separate from the coordinator's named volumes.
Build-job counts alone do not provide a hard CPU or memory limit.

## Required SDK checks

The coordinator runs the focused checks after the SDK build by default.
To repeat just validation, use:

```sh
python scripts/build/qt6-linux-amd64/build-sdk.py --stage checks
```

The direct equivalent, after the build has exited successfully, is:

```sh
mkdir -p artifacts/tests-qt6-linux-amd64-llvm21
docker run --rm --pull never --cpus 4 --memory 8g --network none \
  --entrypoint /bin/bash \
  --mount type=bind,src="$PWD",dst=/src,readonly \
  --mount type=bind,src="$PWD/artifacts/tests-qt6-linux-amd64-llvm21",dst=/out \
  qt6-linux-amd64:llvm21 \
  /src/scripts/tests/qt6-linux-amd64-llvm/run-sdk-checks.sh
```

The runner builds QtCore consumers in C++17/20/23. Older standards retain
named SKIP for unavailable facilities. C++23 sets `SMOKE_REQUIRE_CXX23=ON`
and requires every one of the shared 25 checks to PASS exactly once, with
zero FAIL/SKIP. It also rebuilds the full `qt-selftest` target and runs only
its `--modern-cpp` path with the same strict gate. A qmake QtCore consumer
uses the same required gate. All required runs use
ordinary libc++ 21, without `-fexperimental-library`. Each modern run has
a 60-second timeout. A subsequent ordinary console Qt API run has a
180-second timeout and allows unrelated Qt API SKIP, while requiring all 25
modern checks to PASS. The script does not run security test suites or GUI
galleries; the complete eight-application suite remains separate.

Every generated consumer is screened for the GLIBC 2.17 floor and shared
C++/unwind/libgcc/LLVM runtime dependencies. A stock CentOS 7 container can
additionally run the QtCore-only `modern-cxx23` executable without the SDK
or compiler; containers use the host kernel and do not replace minimum-OS
VM checks.

## Consumer configuration and legacy profiles

Use `/opt/qt6-linux-amd64-llvm/bin/qt-cmake` with the exported `CC`/`CXX`
wrappers. For qmake projects, pass `QMAKE_CC=$CC`, `QMAKE_CXX=$CXX` and
`QMAKE_LINK=$CXX`; the SDK checks exercise this configuration too. Calling
raw clang++ bypasses runtime selection. Select
`-DCMAKE_CXX_STANDARD=23` and pass `-DCMAKE_EXE_LINKER_FLAGS=-no-pie`:
the reused Wayland C stub archives contain non-PIC objects. Qt itself uses
the language modes selected by its projects. The wrappers still use the
seed GCC installation for system startup objects and C platform headers.

Qt 6 requires C++17 or newer. The shared modern-check header remains
C++14-compatible for Qt 4/5 builds; strict C++23 is an explicit profile.
The existing LLVM 19 images remain available with their original wrappers.
Their historical runner is `run-suite.sh` in this directory's scripts tree;
it uses `-fexperimental-library` for the required jthread/stop-token run.
LLVM 19 recipes and fingerprints are preserved in Git history and the
[earlier SDK report](../results/qt6-linux-amd64-llvm-20261108.md).

Docker directories contain Dockerfiles only. Build helpers, wrappers and
the resource-limited coordinator live under
`scripts/build/qt6-linux-amd64/`; SDK checks live under
`scripts/tests/qt6-linux-amd64-llvm/`.

See the [recorded LLVM 21 SDK validation](../results/qt6-linux-amd64-llvm21-sdk-20261110.md)
for build identities, exact counts and execution scope.
