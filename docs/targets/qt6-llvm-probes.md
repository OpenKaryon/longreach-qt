# Qt 6 target toolchain probes: upstream LLVM 21.1.8

These standalone programs test the proposed compiler and C++ runtime before
rebuilding Qt. They do not use Qt or certify the full Qt SDKs. The existing
Qt images and self-tests are unchanged.

## Inputs and floors

The compiler is upstream Clang/LLD 21.1.8, built once on CentOS 7 with the
X86 and AArch64 backends. Each target gets separate static C++ libraries
and its own compiler-rt resource directory. No LLVM-MinGW package or
compiler is used. Windows uses separately built mingw-w64 13.0.0 headers,
CRT objects and import libraries; those remain necessary for the GNU
Windows ABI. Source URLs and SHA256 pins are recorded in
[`inputs.json`](../../scripts/build/qt6-llvm-probes/inputs.json).

| Target | Required runtime floor | Probe execution |
|---|---|---|
| Linux amd64 | glibc 2.17 | Native CentOS 7 userland |
| Linux arm64 | glibc 2.17 | QEMU with the CentOS 7 sysroot |
| Windows amd64 | Windows 7 SP1, MSVCRT | Host console first; Windows 7 VM separately |
| Windows arm64 | Windows 10, UCRT | Native arm64 execution remains separate |
| macOS amd64 | 10.13 | Mach-O audit first; High Sierra VM separately |
| macOS arm64 | 11.0 | Mach-O audit first; native arm64 execution separately |

libc++ 21's versioned platform documentation still lists macOS 10.13.
Its official Linux coverage starts at glibc 2.24, so our 2.17 floor must be
established by the built binaries and runtime checks, not assumed from the
LLVM version. See the [versioned upstream platform documentation](https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-21.1.8/libcxx/docs/index.rst).

## Probe contract

[`main.cpp`](../../scripts/tests/qt6-llvm-probes/main.cpp) checks the same
16 language/library facilities as the existing modern-C++ example checks.
It requires C++23 and libc++ 21 at compilation, and ordinary-library
`jthread`/`stop_token` support without `-fexperimental-library`. Missing
facilities fail compilation; runtime checks do not use SKIP.

The checks cover lambdas, structured bindings, folds, optional, string_view,
concepts, span, ranges, jthread, stop tokens/callbacks, format, if consteval,
expected, byteswap, ranges::to and print to a temporary file. Passing them
does not establish complete C++23 conformance.

## Sequential builds

Fetch the LLVM and Windows CRT archives through `scripts/fetch/fetch.py`
using the URLs and hashes in the input record. Existing SDK images supply
the locked CentOS 7 sysroots and macOS SDK. Build steps have no network.

The shared compiler recipe is
[`Dockerfile-llvm`](../../docker/qt6/host/Dockerfile-llvm); all helper scripts
live under scripts/. For a hard 4-CPU/8-GiB bound, run its helper in a
container instead of relying on build-job counts alone:

```sh
docker create --name longreach-llvm21-compiler --cpus 4 --memory 8g \
  --network none --entrypoint /bin/bash \
  --mount type=bind,src="$PWD",dst=/src,readonly \
  --mount type=volume,src=longreach-llvm21-probes-build,dst=/work \
  --env PARALLEL_JOBS=4 qt6-linux-amd64:centos7-rpm-lock-check \
  /src/scripts/build/qt6-llvm-probes/build-compiler.sh
docker start -a longreach-llvm21-compiler
```

Only after the compiler container exits successfully, preserve its installed
compiler in a local image and copy it into the shared work volume:

```sh
test "$(docker inspect -f '{{.State.ExitCode}}' longreach-llvm21-compiler)" = 0
docker commit longreach-llvm21-compiler longreach-llvm:21.1.8-compiler
docker run --rm --pull never --cpus 1 --memory 1g --network none \
  --entrypoint /bin/bash \
  --mount type=volume,src=longreach-llvm21-probes-build,dst=/work \
  longreach-llvm:21.1.8-compiler \
  -c 'test ! -e /work/toolchain && cp -a /opt/llvm-21 /work/toolchain'
```

The macOS SDK images do not include Python. Copy the build-only Debian 12
interpreter and its standard library into the work volume before the macOS
stages; the target programs do not depend on Python:

```sh
docker run --rm --pull never --cpus 1 --memory 1g --network none \
  --entrypoint /bin/bash \
  --mount type=bind,src="$PWD",dst=/src,readonly \
  --mount type=volume,src=longreach-llvm21-probes-build,dst=/work \
  qt6-linux-arm64:latest /src/scripts/build/qt6-llvm-probes/prepare-host-tools.sh
```

Then run the probes individually or let the runner select all six in order:

```sh
python scripts/tests/qt6-llvm-probes/run.py --target linux-amd64
python scripts/tests/qt6-llvm-probes/run.py
```

The runner holds the existing SDK build lock, refuses to start while another
container is running, limits each build container to 4 CPUs and 8 GiB, and
stops after the first failure. It records builds separately from execution.
On Windows, only the amd64 console probe executes on the host, with local
error-dialog suppression and a timeout. It never launches GUI examples or VMs.

Artifacts and per-target records are saved under
`artifacts/probes-qt6-llvm21/`; full build logs remain under
`build/llvm21-probes/`. Linux binaries are screened against GLIBC 2.17 and
unexpected shared C++ runtime dependencies. The Windows amd64 import screen
and macOS deployment audit do not replace runtime tests on the minimum OS.

See the [six-target probe results](../results/qt6-llvm21-probes-20261110.md) for the recorded run and remaining native-platform checks.
