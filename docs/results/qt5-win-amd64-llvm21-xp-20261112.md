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

This standalone probe exercised Clang and libc++ on the Windows 11 host.

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
nine executables and app-local CRT.

## Windows XP x64 SP2 guest run

On 2026-11-14, the same VMware Workstation guest used for the Qt 4 AMD64
run reported Windows XP x64 SP2 (5.2.3790, AMD64). The Qt 5.15.19 binaries
built with LLVM and libc++ 21.1.8 matched the current repository export
manifest. In the guest, all nine executables and the app-local Visual C++
2010 SP1 CRT matched the verified ISO copies byte for byte.

`qt-selftest.exe --modern-cpp` exited with code 0 and reported
`__cplusplus=202302`. `scripts/tests/require-modern-cpp.py` confirmed
**25/25 required checks, 0 failures, 0 skips**.

`smoke-runner.exe --timeout=180` then ran all eight applications.
**Six passed and two crashed**. The runner exited with code 1.

| Application | Result | Checks or last completed check |
|---|---|---|
| `qt-selftest` | Crash (`0xC0000005`) | `script/value-object-props` |
| `widgets-gallery` | Pass | 94 passed, 5 skipped |
| `graphics-gallery` | Pass | 32 passed, 0 skipped |
| `quick-qml-gallery` | Crash (`0xC0000005`) | `scenegraph/grab-without-window` |
| `gl-heavy-gallery` | Pass | 39 passed, 7 skipped |
| `painting-lab` | Pass | 16 passed, 3 skipped |
| `multimedia-lab` | Pass | 4 passed, 0 skipped |
| `network-gui` | Pass | 7 passed, 0 skipped |

The ordinary `qt-selftest --selftest` run faulted at RVA `0x005F3BC9`.
`quick-qml-gallery` logged the access violation and the runner reported
its exit code as 128. A second run with `QV4_FORCE_INTERPRETER=1` gave
the same 25/25 C++23 result and reproduced both crashes at the same
points.

The [JSON record](qt5-win-amd64-llvm21-xp-20261112.json) records the
settings, exit codes and log hashes for both baseline runs. The local raw logs
are under `build/qt5-xp-x64-guest-verification/initial/` and
`build/qt5-xp-x64-guest-verification/interpreter/`.

### Crash diagnosis and fixes

Linker maps and the original machine code placed the first QtScript
crash in the interpreter's return opcode. Clang removed a low-bit test
on a tagged host call frame because it assumed that the C++ `this`
pointer was aligned. The interpreter then attempted to resume a
bytecode stream from a null return address. The patch tests and strips
the tag on the raw pointer.

The Quick gallery crash went through `QOpenGLFramebufferObject::bindDefault()`.
The guest exposes OpenGL 1.1, so a current context alone is insufficient
for the Qt 5 scene graph renderer exercise. The check now requires
framebuffer objects and shaders. The other Quick checks still run.

The first rebuilt suite passed seven of eight applications. It passed
`script/function-call-context` and the Quick gallery, then exposed a
separate QtScript crash in `script/engine-debugger`. In that check the
collector calls the AMD64 CRT's `_setjmp` to save registers. The old
alignment annotation put the buffer at an address aligned to 8 bytes,
while the CRT saves XMM registers with 16-byte aligned stores. The
collector now explicitly aligns that buffer to 16 bytes on Windows AMD64.

### Final run after the fixes

The standard `make qt5-win-amd64-llvm-examples PARALLEL_JOBS=3` target
rebuilt the SDK and all nine executables. The final guest run used the
same Windows XP x64 SP2 VM and the same app-local CRT. All ten files
matched the verified ISO copies byte for byte.

The strict C++23 run passed **25/25 with zero skips**. The ordinary
suite passed **8/8 applications**, with 504 checks passed, 0 failed and
96 optional skips. Both commands exited with code 0.

| Application | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `qt-selftest` | 288 | 0 | 67 |
| `widgets-gallery` | 94 | 0 | 5 |
| `graphics-gallery` | 32 | 0 | 0 |
| `quick-qml-gallery` | 24 | 0 | 14 |
| `gl-heavy-gallery` | 39 | 0 | 7 |
| `painting-lab` | 16 | 0 | 3 |
| `multimedia-lab` | 4 | 0 | 0 |
| `network-gui` | 7 | 0 | 0 |

`script/function-call-context` and `script/engine-debugger` passed.
The OpenGL 1.1 driver skipped `scenegraph/qt5-engine-renderer` because
the required graphics features were unavailable.
`scenegraph/qt5-rhi-material-shader` passed.

The [JSON record](qt5-win-amd64-llvm21-xp-20261112.json) includes the
final image, executable and log hashes. The raw final logs are under
`build/qt5-xp-x64-guest-verification/fixed/`.
