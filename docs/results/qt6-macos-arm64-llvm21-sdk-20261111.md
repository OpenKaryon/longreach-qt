# Qt 6.8.5 macOS arm64 SDK with LLVM 21.1.8

The 2026-11-11 run installed static Qt in `qt6-macos-arm64:llvm21` at
`/opt/qt6-macos-arm64-llvm`. It used upstream Clang, Mach-O LLD and LLVM
C++ runtimes with the pinned MacOSX 14.0 SDK and an 11.0 deployment floor.
The [run record](qt6-macos-arm64-llvm21-sdk-20261111.json) contains image
IDs, source and executable hashes, compiler commands and dependency checks.

Docker Desktop stopped during the initial Qt build. The coordinator
resumed the retained container and object volume after Docker restarted.
The resumed Qt build and image save took 42 min 29 s with four CPUs,
8 GiB and networking disabled.

| Check | Result |
|---|---|
| Static Qt SDK build and install | PASS |
| Installed LLVM runtime and QtCore, required C++23 | Compiled and linked |
| Guarded QtCore C++17 and C++20 consumers | Compiled and linked |
| QtCore Mach-O architecture, deployment and dependencies | arm64, macOS 11.0, static Qt and LLVM C++ runtimes |
| C++23 execution on Apple silicon | Pending. A matching macOS ARM64 host or guest is needed. |

The C++23 consumer compiles the shared required modern C++ checks without
`-fexperimental-library`. The required mode rejects unavailable features
at compile time. Runtime PASS, FAIL and SKIP counts are unavailable for
this SDK. The GUI galleries and security tests were outside the run scope.

## Reproduce

Stage the [pinned LLVM sources](../../scripts/build/qt6-llvm-probes/inputs.json),
the Qt 6.8.5 source archive, the shared upstream compiler and native Qt
host-tools images, the local Debian-based build seed and the
`qt6-macos-arm64:latest` image that provides the pinned MacOSX SDK. Run from
the repository root with Docker idle.

```powershell
python scripts/build/qt6-llvm-sdk/run.py --target macos-arm64 --wait
```

Use `--stage checks` to repeat compilation and the Mach-O checks against
the saved SDK. For the pending runtime validation, run `modern-cxx23` and
`installed-toolchain-cxx23` from `artifacts/tests-qt6-macos-arm64-llvm21/`
on Apple silicon, record the OS version and process exit code, and validate
the console logs with `scripts/tests/require-modern-cpp.py`.
