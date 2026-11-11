# Qt 6.8.5 Windows arm64 SDK with LLVM 21.1.8

The 2026-11-11 run installed static Qt in `qt6-win-arm64:llvm21` at
`/opt/qt6-windows-arm64-llvm`. It used upstream Clang and LLD, LLVM C++
runtimes and source-built mingw-w64 13.0.0 headers and UCRT import libraries.
The [run record](qt6-windows-arm64-llvm21-sdk-20261111.json) contains image
IDs, source and executable hashes, compiler commands and binary headers.

The toolchain and Qt use the Windows 10 header definitions. The SDK
build resumed from the retained object volume after aligning the spelling
of the version macros passed by Qt and the compiler wrapper. The resumed
Qt build and image save took 37 min 16 s with four CPUs, 8 GiB and
networking disabled.

| Check | Result |
|---|---|
| Static Qt SDK build and install | PASS |
| Installed LLVM runtime and QtCore, required C++23 | Compiled and linked |
| Guarded QtCore C++17 and C++20 consumers | Compiled and linked |
| QtCore PE headers and imports | ARM64, subsystem 10.0, static Qt and LLVM C++ runtimes |
| C++23 execution on Windows on ARM | Pending. The local host is x64 and there is no configured Windows ARM64 runtime. |

The C++23 consumer compiles the shared required modern C++ checks without
`-fexperimental-library`. The required mode rejects unavailable features
at compile time. Runtime PASS, FAIL and SKIP counts are unavailable for
this SDK. The GUI galleries and security tests were outside the run scope.

## Reproduce

Stage the [pinned LLVM and mingw-w64 inputs](../../scripts/build/qt6-llvm-probes/inputs.json),
the Qt 6.8.5 source archive, the shared upstream compiler and native Qt
host-tools images and the local Debian-based build seed. Run from the
repository root with Docker idle.

```powershell
python scripts/build/qt6-llvm-sdk/run.py --target windows-arm64 --wait
```

Use `--stage checks` to repeat compilation and the PE checks against the
saved SDK. For the pending runtime validation, run
`artifacts/tests-qt6-windows-arm64-llvm21/modern-cxx23.exe` on Windows on
ARM, record the OS version and process exit code, and validate the console
log with `scripts/tests/require-modern-cpp.py`. Also run the standalone
`installed-toolchain-cxx23.exe` from the same directory.
