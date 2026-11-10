# Qt 6 Windows amd64 LLVM consumer profile

The ordinary Windows amd64 SDK already uses LLVM-MinGW 20241217 / Clang
19.1.6 and libc++ with MSVCRT. `Dockerfile-llvm` reuses that installed Qt
6.8.5 SDK and adds Git, Python 3, a native host compiler (for tools such as
protoc), and the pinned Kitware CMake 3.28.6 binary. Qt and LLVM are not
rebuilt or replaced. The existing default target remains unchanged.

The SDK remains a Linux-hosted cross-compilation image that produces
native Windows PE executables; no LLVM VM or runtime compiler is needed
on the destination system.

## Build

From the repository root, prepare the ordinary SDK and the existing pinned
CMake archive (`downloads/cmake-3.28.6-linux-x86_64.tar.gz`, SHA256
`931e3c0d546ee03ca72bb147ccd9b49e3b6252f765f66bf21b9d165519940458`):

```sh
make -j1 qt6-win-amd64 PARALLEL_JOBS=4
python scripts/fetch/fetch.py \
  https://github.com/Kitware/CMake/releases/download/v3.28.6/cmake-3.28.6-linux-x86_64.tar.gz \
  downloads/cmake-3.28.6-linux-x86_64.tar.gz \
  931e3c0d546ee03ca72bb147ccd9b49e3b6252f765f66bf21b9d165519940458
docker build --progress=plain \
  -f docker/qt6/windows/amd64/Dockerfile-llvm \
  -t qt6-win-amd64:llvm19-pilot .
```

Host build packages use the repository's Debian snapshot setup. The
compiler and Qt come from `QT6_WINDOWS_BASE_IMAGE` (default
`qt6-win-amd64`); use the recorded image identity when reproducing a run.
The Docker directory contains only Dockerfiles; helpers live in scripts/.

## Sequential checks

After the image build finishes:

```sh
mkdir -p artifacts/tests-qt6-win-amd64-llvm19
docker run --rm --pull never --cpus 4 --memory 8g --network none \
  --entrypoint /bin/bash \
  --mount type=bind,src="$PWD",dst=/src,readonly \
  --mount type=bind,src="$PWD/artifacts/tests-qt6-win-amd64-llvm19",dst=/out \
  qt6-win-amd64:llvm19-pilot /src/scripts/tests/qt6-win-amd64-llvm/build-suite.sh
```

This builds all eight ordinary applications and smoke-runner in C++23
mode, a separate experimental console self-test, and ordinary/experimental
QtCore-only language probes. The PE import/subsystem audit runs without
executing the cross-built programs. It screens known Windows 8+ loader
dependencies; it does not establish that an application works on Windows 7.

Then, on Windows, check the ordinary console first:

```powershell
python scripts/tests/qt6-win-amd64-llvm/run-suite.py --only qt-selftest
python scripts/tests/qt6-win-amd64-llvm/run-suite.py --only qt-selftest-experimental
```

The experimental executable uses `-fexperimental-library` at compilation
and linking; jthread and stop-token/callback checks must report PASS.

The Windows runner explicitly selects the native `windows` platform.
The suite contains Windows OpenGL checks that the offscreen backend
cannot provide; the runner does not offer that backend. It writes Qt diagnostics
to files, stops at the first failed process/check and restores its local
process error mode afterwards. Its child-process error handling uses
[SetErrorMode](https://learn.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-seterrormode);
it does not change system-wide Windows Error Reporting settings.

Calling the runner without `--only` selects the full sequential application
set, followed by the separate experimental console and language probes.
Only do that after the single-console preflight passes. Source-built
consumers must compile their C++ dependencies with the
same LLVM-MinGW toolchain and compatible C++ library settings.

See the [recorded validation](../results/qt6-win-amd64-llvm-consumer-20261108.md)
for the exact native-runtime scope and consumer checks.
