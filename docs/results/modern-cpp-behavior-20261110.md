# Required modern-C++ behavior checks, 2026-11-10

The Qt self-test and standalone LLVM 21 probes now share 25 checks. Nine new
checks exercise cancellation of a condition-variable wait, jthread destructor
stop/join, atomic wait/notify, thread-local destruction, exception unwinding
and RAII, Unicode filesystem round trips, format_error, expected monadic
error propagation and Unicode format/print. These are ordinary API correctness
checks. The [JSON record](modern-cpp-behavior-20261110.json) contains source and
binary hashes, image identities, captured output and execution limits.

## Required run

`SMOKE_REQUIRE_CXX23=ON` requires C++23 at configure/compile time. An unavailable
facility becomes FAIL. The [required-check gate](../../scripts/tests/require-modern-cpp.py)
requires all 25 manifest names to PASS exactly once, a C++23 language record
and a matching summary. A missing check, duplicate, FAIL, SKIP or incomplete
summary fails the required modern-only run. The optional complete-console
mode permits unrelated Qt API SKIP but requires all modern checks to PASS.

`qt-selftest --modern-cpp` runs just the shared checks and exits with their
summary. The QtCore-only drivers exercise the same code without initializing
the GUI. Legacy/default builds retain feature guards and named SKIP.

## Standalone upstream LLVM 21.1.8

| Target | Compile/link and binary audit | Execution |
|---|---|---|
| Linux amd64 | PASS, GLIBC <= 2.17 | 25 PASS, 0 FAIL, 0 SKIP, native CentOS 7 userland |
| Linux arm64 | PASS, GLIBC <= 2.17 | 25 PASS, 0 FAIL, 0 SKIP, QEMU with CentOS 7 sysroot |
| Windows amd64 | PASS, PE subsystem 6.1 and Win7 import screen | 25 PASS, 0 FAIL, 0 SKIP, Windows 11 host |
| Windows arm64 | PASS, ARM64 PE subsystem 10.0 | Not run |
| macOS amd64 | PASS, Mach-O floor 10.13 and runtime archive architectures | Not run |
| macOS arm64 | PASS, Mach-O floor 11.0 and runtime archive architectures | Not run |

All six use upstream Clang/LLD, libc++, libc++abi, libunwind and compiler-rt
21.1.8 without the experimental-library flag or an LLVM-MinGW distribution.
Windows separately uses source-built mingw-w64 13.0.0 headers/CRT/import
libraries. Linux has no shared C++/unwind/libgcc runtime dependency. Windows
amd64 imports only KERNEL32.dll and msvcrt.dll; both macOS binaries link only
libSystem dynamically. Binary audits do not certify minimum-OS execution.

The new TLS-destructor check exposed an arm64 cross-configuration error:
compile-only CMake tests selected `__cxa_thread_atexit_impl`, absent from the
glibc 2.17 sysroot. Linux now explicitly sets
`LIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF`, selecting libc++abi's existing
weak-symbol/TLS fallback. Both Linux targets were rebuilt and passed all 25
checks afterwards. LLVM sources were not patched. Upstream fallback limits
for shared-object unloading and main-thread destruction order still apply;
the test covers destruction on a joined worker thread.

## Existing Qt SDK integration and older standards

| SDK and mode | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Qt 6 Linux, LLVM 19, C++17 ordinary | 7 | 0 | 18 |
| Qt 6 Linux, LLVM 19, C++20 ordinary | 12 | 0 | 13 |
| Qt 6 Linux, LLVM 19, C++23 ordinary | 19 | 0 | 6 |
| Qt 6 Linux, LLVM 19, required C++23 QtCore driver | 25 | 0 | 0 |
| Qt 6 Linux, LLVM 19, required C++23 qt-selftest --modern-cpp | 25 | 0 | 0 |
| Qt 6 Windows, LLVM 19, C++23 ordinary QtCore driver | 19 | 0 | 6 |
| Qt 6 Windows, LLVM 19, required C++23 QtCore driver | 25 | 0 | 0 |
| Qt 4 Linux, GCC 5.4, C++14 QtCore driver | 2 | 0 | 23 |

Required LLVM 19 runs use `-fexperimental-library` during compilation and
linking. The full Linux Qt console target was rebuilt and only its
`--modern-cpp` path was executed under Xvfb/offscreen. Windows runs were
plain console drivers with process-local error-dialog suppression and a
timeout. The Qt 4 run used qmake, GCC 5.4 and the Sarge loader/sysroot; generic
lambdas and exception/RAII passed, while unsupported features remained SKIP.
Qt 6 itself requires at least C++17; C++14 compatibility was checked on Qt 4.

Control checks confirmed that the gate rejects the real ordinary C++23 log
with six SKIP, a removed or duplicated required check, a missing summary and
an unrelated SKIP in modern-only mode. Complete-console mode accepts only
the unrelated Qt SKIP. CMake rejected required C++23 configured as C++20.
Changed Python files compiled, shell syntax checks and git diff checks passed.

## Scope and reproduction

The shared compiler/runtime volume from the [probe guide](../targets/qt6-llvm-probes.md)
was reused. All Docker builds/runs were sequential, with network disabled
and at most four CPUs / 8 GiB. Build logs remain under `build/llvm21-probes/`
and `build/modern-*-validation.log`; executables and runtime logs are under
`artifacts/probes-qt6-llvm21-behavior/` and
`artifacts/modern-cpp-behavior-20261110/`.

```sh
python scripts/tests/qt6-llvm-probes/run.py --suite artifacts/probes-qt6-llvm21-behavior
python scripts/tests/require-modern-cpp.py artifacts/probes-qt6-llvm21-behavior/linux-amd64/run.log
```

For a focused QtCore run, configure the appropriate
`scripts/tests/qt6-{linux,win}-amd64-llvm` CMake project against the existing
SDK with `CMAKE_CXX_STANDARD=23` and `SMOKE_REQUIRE_CXX23=ON`; LLVM 19 also needs
`-fexperimental-library` for compilation/linking. Linux additionally needs
the profile's `-no-pie` linker flag. Run `modern-only`, capture stdout and
apply the same gate. The existing Linux/Windows suite scripts now set these
required flags and gate the required modern section/probe.

No security tests, GUI galleries or virtual machines were launched. Full
LLVM 21 Qt SDK rebuilds, macOS/Windows arm64 execution and minimum-OS VM
checks remain separate. The [original 16-check report](qt6-llvm21-probes-20261110.md)
retains its historical results unchanged. All changes are local; no push.
