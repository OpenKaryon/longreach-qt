# LLVM 21.1.8 for Qt 5.15.19 on Windows amd64

## Standalone runtime probe

Clang 21.1.8 and libc++ 21.1.8 built the standalone probe in C++23 mode
(`__cplusplus=202302`). The target uses the XP x64 MinGW-w64 v5 sysroot.
The `stralign.h` inline wide-character search wrappers now cast the
aligned return value to their declared return type, matching the existing
unaligned branch.

The PE machine is AMD64 and the subsystem version is 5.2. The probe
imports `KERNEL32.dll`, `USER32.dll` and `msvcr100.dll`. It ran on the
Windows 11 x64 host (build 26200) with app-local Visual C++ 2010 CRT
10.00.40219.325 and passed **25 of 25 checks, 0 failures, 0 skips**.

| File | SHA256 |
|---|---|
| `cxx23-probe.exe` | `0a4bde0d4d395ea3cdd0cc8664e41a3695ededd5c0d8be53ae0511aa78426341` |
| `msvcr100.dll` | `ae3cb6c6afba9a4aa5c85f66023c35338ca579b30326dd02918f9d55259503d5` |

The PE subsystem version records the target. The loader and runtime on
Windows XP x64 SP2 still need a guest run. The standalone probe does
not use the Qt libraries.

## SDK build recipe

The shared Windows XP Docker recipe selects the AMD64 sysroot and copies
only its OpenSSL headers and `lib64` archives. The original AMD64 image
also has a `lib` directory containing ARM64 ELF archives, which Qt's
OpenSSL detection searches first when that directory is present. The
AMD64 recipe also guards the old MinGW `_xgetbv` definition when Clang
already provides it.

```sh
make qt5-win-amd64-llvm-examples PARALLEL_JOBS=3
```

## Staged SDK and examples

The staged SDK built successfully with linked OpenSSL. All 235 static
archive paths matched the existing Windows amd64 SDK. CMake built all
nine example executables in strict C++23 mode. The PE audit confirmed
AMD64, subsystem 5.2 and the app-local Visual C++ 2010 CRT. The
[JSON record](qt5-win-amd64-llvm21-xp-20261112.json) contains the hashes
and import lists. Compared with the original amd64 executables, the only
new direct Windows system imports are five functions from the kernel32.dll
import table. The audit also checked all CRT imports against the app-local
msvcr100.dll export table. The clean repository build then repeated the SDK and example build.

## Clean repository build and runtime

The repository recipe reproduced all 235 archive paths and built nine
PE32+ AMD64 examples with subsystem version 5.2. The executable hashes
are in the JSON record.
All 157 qmake module files and 314 qmake feature entries matched the existing SDK.

On Windows 11 x64 (build 26200), the Qt-linked C++23 self-test passed all
25 required checks from E:. From C:, the Windows CRT's `tmpfile` needed
write access to the drive root, so two print checks initially failed
before printing. Both passed after the test fixture was changed to use
the user's temporary directory. The fixture-only rebuild used the same
installed SDK and passed all 25 checks from C: without skips.
[Microsoft CRT documentation](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/tmpfile).

All seven ordinary GUI examples passed on Windows 11 with the app-local
CRT. Their reports contained 235 passes, 0 failures and 23 optional
skips.

The Windows 7 SP1 x64 guest (build 6.1.7601) passed all 25 required
C++23 checks and all seven GUI examples. The GUI total was 236 passed,
0 failed and 22 optional skips. The guest used the repository binaries,
the app-local Visual C++ 2010 CRT and the selftest rebuilt with the
print fixture correction. All ten files were verified after transfer.
Windows XP x64 SP2 runtime compatibility remains unverified.

A local `qt5-llvm21-xp-x64-sp2-test-kit.zip` packages the nine tested
executables, the app-local CRT, their SHA-256 checksums and an XP x64 SP2
runner. The runner checks the guest edition, service pack and architecture
before starting the strict C++23 and seven ordinary GUI checks. The OS
guard rejected Windows 11. A local copy with the guard omitted passed all
eight invocations there and recorded their exit codes.

## Current repository export

The standard Make recipe rebuilt the SDK and exported all nine examples
with the print fixture correction. Every executable matched the new
manifest and used AMD64 PE32+ with subsystem version 5.2. All nine hashes
differed from the prior Windows 7 run, so the fresh export was rerun.
The direct PE imports matched the earlier Windows 7 suite for all nine
executables. Every CRT import was present in the app-local msvcr100.dll.
The fresh SDK matched all 235 baseline archive paths, 157 qmake module
files and 314 qmake feature entries.

Windows 7 SP1 x64 passed all 25 required C++23 checks and all seven GUI
examples, with 236 GUI checks passed, 0 failed and 22 optional skips.
The local `qt5-llvm21-xp-x64-sp2-current-export.zip` contains the same
nine executables and app-local CRT. The XP x64 SP2 run is deferred until installation media or a guest is available.
