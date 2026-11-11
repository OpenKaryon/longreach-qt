# Qt 6.8.5 Windows amd64 SDK with LLVM 21.1.8

The 2026-11-11 run installed the static Qt SDK in
`qt6-win-amd64:llvm21` at `/opt/qt6-windows-amd64-llvm`.
It used upstream Clang/LLD and the LLVM C++ runtimes with source-built
mingw-w64 13.0.0 headers and MSVCRT import libraries. The
[run record](qt6-windows-amd64-llvm21-sdk-20261111.json) contains image IDs,
source and executable hashes, compiler commands and console logs.

The Qt build and image save took about 54 minutes across three attempts
using one container with four CPUs, 8 GiB and networking disabled. The
resumed build reused Qt objects after two source fixes. The Windows QPA
plugin now includes `qoperatingsystemversion.h` directly for builds without
precompiled headers. PhysX now uses the installed `winsock2.h` spelling
on case-sensitive hosts.

| Run | Environment | PASS | FAIL | SKIP |
|---|---|---:|---:|---:|
| Installed LLVM runtime, required C++23 | Native Windows 11, build 26200 | 25 | 0 | 0 |
| QtCore, C++17 | Native Windows 11, build 26200 | 7 | 0 | 18 |
| QtCore, C++20 | Native Windows 11, build 26200 | 18 | 0 | 7 |
| QtCore, required C++23 | Native Windows 11, build 26200 | 25 | 0 | 0 |
| QtCore, required C++23 | VMware Windows 7 SP1, build 7601 | 25 | 0 | 0 |
| QtCore, required C++23 | VMware Windows 11, build 26200.9711 | 25 | 0 | 0 |

The required runs used libc++ 21.1.8 without `-fexperimental-library`.
The QtCore consumers use the shared modern C++ section of `qt-selftest`.
Older modes skip features from later standards. The PE64 binaries passed
the Windows 7 subsystem and import checks and link Qt and the LLVM C++
runtimes statically. Both VMware logs include the OS version and a zero
process exit code. The build covered the configured static Qt modules.
The GUI galleries and security tests were outside the run scope.

## Reproduce

Stage the [pinned sources and local images](../targets/qt6-windows-llvm.md)
and run from the repository root with Docker idle.

```powershell
python scripts/build/qt6-llvm-sdk/run.py --target windows-amd64 --wait
```

Use `--stage checks` to repeat the checks against the saved SDK image and
`--stage qt --resume --wait` to continue a retained Qt build with the same inputs. The coordinator
writes build logs to `build/` and executable and test evidence to
`artifacts/tests-qt6-windows-amd64-llvm21/`. For a guest test, copy
`modern-cxx23.exe` from that directory, record the guest OS version and
program exit code, and run `scripts/tests/require-modern-cpp.py` against
the captured console output.
