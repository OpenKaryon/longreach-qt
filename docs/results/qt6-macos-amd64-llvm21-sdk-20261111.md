# Qt 6.8.5 macOS amd64 SDK with LLVM 21.1.8

The 2026-11-11 run installed static Qt in `qt6-macos-amd64:llvm21` at
`/opt/qt6-macos-amd64-llvm`. It used upstream Clang, Mach-O LLD and LLVM
C++ runtimes with the pinned MacOSX 14.0 SDK and a 10.13 deployment floor.
The [run record](qt6-macos-amd64-llvm21-sdk-20261111.json) contains the
image IDs, source and executable hashes, compiler commands and run evidence.

The resumed Qt build and image save took 46 min 55 s in a single container
with four CPUs, 8 GiB and networking disabled. The IOKit default-port patch
now includes context for `git apply`. The QtCore consumers link the Qt and
LLVM C++ runtimes statically. The Mach-O audit checks x86-64, deployment
target 10.13 and the aligned-allocation symbols. The C++23 build uses the
shared required manifest and ordinary libc++ 21.1.8.

## High Sierra 10.13.6 runtime

The console programs ran over SSH in the restored clean x86-64 VMware
guest. The guest ran by itself with one CPU and 4 GiB and was suspended
after the checks. The initial SDK coordinator recorded a pending runtime
while that guest was offline. The subsequent runtime evidence is included
in the run record.

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Installed LLVM runtime, required C++23 | 25 | 0 | 0 |
| QtCore, C++17 | 7 | 0 | 18 |
| QtCore, C++20 | 18 | 0 | 7 |
| QtCore, required C++23 | 25 | 0 | 0 |

Older modes skip features from later standards. The GUI galleries and
security tests were outside the run scope.

## Reproduce

Stage the [pinned LLVM sources](../../scripts/build/qt6-llvm-probes/inputs.json),
Qt 6.8.5 sources, the shared upstream compiler and native Qt host-tools
images, the Debian-based target seed and the `qt6-macos-amd64:latest` image
that provides the pinned MacOSX SDK. Run from the repository root with Docker
idle.

```powershell
python scripts/build/qt6-llvm-sdk/run.py --target macos-amd64 --wait
```

Use `--stage checks` to repeat the consumer checks against the saved image.
The coordinator writes its logs to `build/` and binaries to
`artifacts/tests-qt6-macos-amd64-llvm21/`. To repeat the runtime test, run the
compiled console programs in a macOS amd64 guest, record its OS version and
check the C++23 output with `scripts/tests/require-modern-cpp.py`.
