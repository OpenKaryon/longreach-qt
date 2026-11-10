# Upstream LLVM 21.1.8: six target probes

On 2026-11-10 UTC, standalone C++23 probes built successfully for all six
Qt 6 target combinations with upstream Clang/LLD and static LLVM C++ runtimes
21.1.8. These programs do not link Qt; the existing Qt SDKs and tests/ tree
were not changed. The [JSON record](qt6-llvm21-probes-20261110.json) contains
source/binary hashes, image identities, dependencies and execution scope.

| Target | Required floor | Compile/link | Execution |
|---|---|---|---|
| Linux amd64 | glibc 2.17 | PASS | 16 PASS, 0 FAIL, 0 SKIP in CentOS 7 userland |
| Linux arm64 | glibc 2.17 | PASS | 16 PASS, 0 FAIL, 0 SKIP under QEMU with CentOS 7 sysroot |
| Windows amd64 | Windows 7 SP1, MSVCRT | PASS | 16 PASS, 0 FAIL, 0 SKIP on Windows 11 host |
| Windows arm64 | Windows 10, UCRT | PASS | Not run |
| macOS amd64 | 10.13 | PASS | Not run |
| macOS arm64 | 11.0 | PASS | Not run |

All compilation requires C++23 and libc++ 21, including ordinary-library
jthread and stop-token support. No experimental-library flag or LLVM-MinGW
distribution is used. Windows headers, startup objects and import libraries
come from separately source-built mingw-w64 13.0.0. Source pins and bounded,
sequential commands are in the [probe guide](../targets/qt6-llvm-probes.md).

Both Linux executables require GLIBC no newer than 2.17 and have no shared
C++/unwind/libgcc runtime dependency. The Windows amd64 PE subsystem is 6.1;
its only imported DLLs are KERNEL32.dll and msvcrt.dll, and the existing
Win7 import screen passes. Windows arm64 is an ARM64 PE with subsystem 10.0.
Both Mach-O binaries declare their requested deployment floors and link
only libSystem dynamically. Each macOS builtins/unwind/ABI/C++ archive is
checked for the requested architecture; linker warnings are fatal.

## Findings before rebuilding Qt

- C and C++ include order must keep libc++ wrappers ahead of the old C
  sysroot headers. Assembly must receive the same explicit compiler target
  as C and C++: otherwise an arm64 archive can contain x86 assembly objects.
- Compile-only CMake checks can falsely report a pthread library as present.
  Windows probes use the runtime's native Win32 thread implementation.
- The 12.0.0 Windows headers hid `_iswctype_l` for MSVCRT; 13.0.0 includes
  the [upstream Vista/MSVCRT declaration fix](https://sourceforge.net/p/mingw-w64/mailman/message/58827388/).
  The program and libc++ still target Windows 7; internal CRT construction
  retains upstream's flags for its complete set of API import libraries.
- Darwin compiler-rt's SDK architecture discovery invokes Apple's PlistBuddy,
  unavailable on Linux. Select the architecture explicitly after checking
  SDKSettings.plist with Python. Without that, the arm64 probe initially
  linked while ignoring an Intel-only builtins archive. Archive validation
  and fatal linker warnings now reject this situation.
- The existing macOS SDK images have no Python interpreter. A build-only
  Debian 12 Python/stdlib copy supplies it without becoming an application
  dependency. No compatibility patches to LLVM/libc++ were needed.

The compiler/bootstrap was built once in a new work volume. Failed attempts
were corrected sequentially, retaining prior logs and reusing valid compiled
objects. All six final runs use identical recorded helper/probe inputs.
One final queue paused for another task's container; it resumed after Docker
became idle. No unrelated container was stopped. No VM, GUI example or
security regression test was run; no new commit, push or release was made.

## Next self-test coverage to discuss

Keep the guarded checks for older language modes, and add a mandatory C++23
run whose required checks cannot SKIP. The next useful behavioral additions
are cooperative jthread cancellation with condition_variable_any and a
deterministic readiness handshake; atomic wait/notify; exception unwinding,
RAII and thread-local destruction; Unicode filesystem I/O and formatting;
and normal error propagation through expected/format. Use temporary files,
one worker and bounded execution, without timing-dependent sleeps.

Carry the probe's actual compiler/library/standard reporting, architecture
and dependency checks into the kit examples. Add a separate compiler-rt
arithmetic check that forces a runtime helper call: language features alone
did not expose the ignored Darwin builtins archive. These stronger checks
have not yet been added to the existing self-test.

Windows 7, High Sierra and native arm64 execution remain separate runtime
validation steps. Compile/link and deployment headers alone do not establish
that every library facility works on the minimum OS.

## Local evidence

- `build/llvm21-probes/compiler-build.log` and per-target build logs.
- `build/llvm21-probes/*-previous-*.log` preserve preceding attempts.
- `artifacts/probes-qt6-llvm21/<target>/`: binaries, dependency/audit logs and
  run logs where execution was available.
- `artifacts/probes-qt6-llvm21/result-<target>.json`: final-attempt receipts.
