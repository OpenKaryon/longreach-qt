# Qt 6 Linux amd64 LLVM pilot

This is a local experiment with Clang/LLD 19.1.6, static libc++, libc++abi,
libunwind and compiler-rt, all built on CentOS 7. The ordinary
`qt6-linux-amd64` make target continues to use GCC. There is no new Makefile
target or published SDK image yet.

The pilot reuses the patched Qt 6.8.5 source and C dependencies in the
locked-RPM GCC SDK, then builds Qt afresh under
`/opt/qt6-linux-amd64-llvm`. It does not rebuild OpenSSL or the operating
system dependencies. The seed's original GCC SDK remains in the image.
This fixed recipe uses the GPL-enabled module set.

Build the seed with the normal pinned sources and local RPMs:

```sh
make -j1 qt6-linux-amd64 PARALLEL_JOBS=4 \
  QT6_LINUX_AMD64_IMAGE=qt6-linux-amd64:centos7-rpm-lock-check \
  DOCKER_BUILD_FLAGS="--network=none --progress=plain"
```

The seed used for the recorded pilot had local image ID
`sha256:7c41b21e376019cfcc5be848d99f6df265ce7aff06213b07a7250942f40271b8`.
Rebuilding it can produce a different image ID. See the
[RPM build report](../results/qt6-linux-amd64-centos7-rpm-lock-20261104.md).

Stage the LLVM archive from the official release. The build context is the
repository root, as for the ordinary Dockerfiles (POSIX shell commands):

```sh
mkdir -p downloads
curl -fL --retry 3 \
  https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.6/llvm-project-19.1.6.src.tar.xz \
  -o downloads/llvm-project-19.1.6.src.tar.xz
docker build --network=none --progress=plain \
  --build-arg PARALLEL_JOBS=4 --target qt \
  -f docker/qt6/linux/amd64/Dockerfile-llvm \
  -t qt6-linux-amd64:llvm19-pilot .
```

The recipe checks SHA256
`e3f79317adaa9196d2cfffe1c869d7c100b7540832bc44fe0d3f44a12861fa34`,
measured from the official HTTPS download for this experiment. This is a
local content pin, not an independently verified upstream signature.
Build steps have networking disabled. The compiler build has one link job;
Qt uses four compile jobs and LLD is limited to two threads per link.

Consumers must use `/opt/qt6-linux-amd64-llvm/bin/qt-cmake` and the exported
`CC`/`CXX` wrappers. Calling the raw `clang++` bypasses the libc++ and runtime
selection. Select modern language checks with `-DCMAKE_CXX_STANDARD=23`.
Consumers must also pass `-DCMAKE_EXE_LINKER_FLAGS=-no-pie`, matching the
seed GCC SDK: the reused Wayland stub archives contain non-PIC objects,
whereas Clang defaults to PIE executables. The smoke script sets this flag.
The Qt libraries themselves use the language level selected by Qt.
The compiler bootstrap uses GCC 11; target Qt and applications use Clang.
The wrappers still use the seed's GCC installation to locate the system
startup objects and platform headers.

## Sequential consumer checks

After the SDK build finishes, build the ordinary eight-app smoke suite in
C++23 mode and run it under Xvfb/offscreen. The same container then builds
the language checks alone in C++17, C++20 and C++23 modes. It verifies the
GLIBC symbol floor for every suite executable and checks that the C++23
probe has no shared C++/LLVM runtime dependency.

The script then builds the full console `qt-selftest` in a separate build
tree with `-fexperimental-library` for both compilation and linking. It
sets `SMOKE_REQUIRE_CXX23=ON`: all 25 shared modern-C++ checks must PASS;
missing checks or modern-section SKIP fail this run. Unrelated Qt API
checks may still report SKIP. The QtCore-only required probe allows no SKIP.
It saves `qt-selftest-experimental` and `qt-selftest-experimental.log`
without replacing the ordinary suite. Finally it builds and runs the
QtCore-only `modern-cxx23-experimental` probe, checks its GLIBC floor and
shared dependencies, and saves its log. All stages run sequentially.

```sh
mkdir -p artifacts/tests-qt6-linux-amd64-llvm19
docker run --rm --pull never --cpus 4 --memory 8g --network none \
  --entrypoint /bin/bash \
  --mount type=bind,src="$PWD",dst=/src,readonly \
  --mount type=bind,src="$PWD/artifacts/tests-qt6-linux-amd64-llvm19",dst=/out \
  qt6-linux-amd64:llvm19-pilot /src/scripts/tests/qt6-linux-amd64-llvm/run-suite.sh
```

This requires the seed's Xvfb and Python 3. Do not run it concurrently with
the SDK build. For a runtime-only check, run `/out/modern-cxx23` in a stock
CentOS 7 container with the artifact directory mounted read-only at `/out`;
the compiler image is not required to execute that binary. Containers
exercise the old userland on the host kernel, not a CentOS 7 kernel.

## Source layout and recorded runs

The recipes `Dockerfile` and `Dockerfile-llvm` live together under
`docker/qt6/linux/amd64/`. Compiler wrappers live under
`scripts/build/qt6-linux-amd64/`; the sequential runner and its small
CMake/console driver live under `scripts/tests/qt6-linux-amd64-llvm/`.
Docker directories contain Dockerfiles only.

Earlier result JSON files retain the input paths and hashes captured at
run time, before this relocation. These historical fingerprints were not
rewritten to describe the current layout. The current commands above use
the relocated files.


## Required C++23 behavior and legacy standards

The default self-test remains compatible with C++14; feature guards retain
named SKIP for unavailable language/library features. Qt 6 itself requires
C++17 or newer. `SMOKE_REQUIRE_CXX23=ON` is an explicit required run: select
`-DCMAKE_CXX_STANDARD=23`, and supply the experimental-library flag when using
libc++ 19. LLVM 21 probes use ordinary libc++ without that flag.

Run only these checks in the full console executable with `--modern-cpp`,
then gate its log:

```sh
python scripts/tests/require-modern-cpp.py modern-required.log
```

The gate requires every manifest check once, a C++23 language record and a
consistent summary. Use `--allow-other-checks` only for a complete Qt console
log, where unrelated Qt API SKIP is expected. The required modern-only run
always requires zero SKIP. See the [expanded behavior results](../results/modern-cpp-behavior-20261110.md).
