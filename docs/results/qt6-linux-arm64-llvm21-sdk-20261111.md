# Qt 6.8.5 Linux arm64 SDK with LLVM 21.1.8

The 2026-11-11 run installed the static Qt SDK in
`qt6-linux-arm64:llvm21` at `/opt/qt6-linux-arm64-llvm`.
The [run record](qt6-linux-arm64-llvm21-sdk-20261111.json) contains image IDs,
source hashes, compiler/linker versions, executable hashes and test logs.
The resumed Qt build and image save took 52 min 35 s with four CPUs, 8 GiB
and networking disabled. The build container exited successfully.

| Run | Environment | PASS | FAIL | SKIP |
|---|---|---:|---:|---:|
| Installed LLVM runtime, C++23 | QEMU with CentOS 7 sysroot | 25 | 0 | 0 |
| QtCore, C++17 | QEMU with CentOS 7 sysroot | 7 | 0 | 18 |
| QtCore, C++20 | QEMU with CentOS 7 sysroot | 18 | 0 | 7 |
| QtCore, required C++23 | QEMU with CentOS 7 sysroot | 25 | 0 | 0 |
| `qt-selftest --modern-cpp`, required C++23 | QEMU with CentOS 7 sysroot | 25 | 0 | 0 |
| QtCore, required C++23 | Stock CentOS 7 arm64 user space under QEMU | 25 | 0 | 0 |
| Shared QtCore checks, C++14 | Qt 4 Linux amd64, GCC 5.4 and qmake | 2 | 0 | 23 |

The required runs used libc++ 21.1.8 without `-fexperimental-library`.
The shared manifest verifies every named check. Required mode also rejects
unsupported features during compilation. Older language modes guard features
introduced by later standards, which accounts for their optional skips.

The AArch64 QtCore and Qt console binaries reference glibc symbols up to
2.17 and link the LLVM C++ runtimes statically. The stock container used
its own CentOS 7 libraries on the Docker host kernel. The Qt console run
covered its modern C++ section. GUI galleries and security tests were
outside the run scope.

## Reproduce

Stage the [pinned LLVM inputs](../../scripts/build/qt6-llvm-probes/inputs.json),
Qt 6.8.5 sources, the `qt6-linux-arm64:latest` sysroot image and the upstream
LLVM compiler and native Qt host-tools images documented in the
[Linux amd64 SDK run](qt6-linux-amd64-llvm21-sdk-20261110.md). Run from the
repository root with Docker idle.

```powershell
python scripts/build/qt6-llvm-sdk/run.py --target linux-arm64 --wait
```

Use `--stage checks` to repeat the consumer tests against the saved image.
Use `--stage qt --resume --wait` to continue a retained Qt build with the same inputs.
The coordinator writes build logs to `build/` and binaries and test logs to
`artifacts/tests-qt6-linux-arm64-llvm21/`. For the separate stock check,
run `modern-cxx23` with static `qemu-aarch64` in `arm64v8/centos:7` using
the image ID in the run record, then validate its output with
`scripts/tests/require-modern-cpp.py`.

Patch 29 uses Clang's ARM yield builtin in QtBase. The target LLVM runtime
uses a separate CMake cache for the SDK compiler location. The native
`qsb` runs with a copied graphics dependency closure, which lets the
cross-build compile shaders against the target SDK.
