# Qt 6.8.5 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt6-win-amd64` | `qt6-win-amd64-llvm21` | Windows 7 SP1 | Upstream LLVM 21.1.8, MSVCRT |
| `make qt6-win-arm64` | `qt6-win-arm64` | Windows 10 on ARM | LLVM-MinGW 20241217, UCRT |

AMD64 uses host tools from the native Linux LLVM SDK. The ARM64 build
continues to use `qt6-host`.
`make qt6-win-amd64-examples` builds the test suite against the SDK into
`artifacts/tests-qt6-win-amd64-llvm21/`; `make qt6-win-amd64-audit` screens every EXE for
Windows 8+ loader dependencies (PE subsystem above 6.1, `api-ms-win-*`,
SHCore, WaitOnAddress, GetDpiForMonitor and similar imports).

## Windows 7

`patches/qt6/windows` is the Windows 7 backport. 01-07 are the diffs of
[crystalidea/qt6windows7](https://github.com/crystalidea/qt6windows7) at
`3df3aac7` against pristine 6.8.4, carried to 6.8.5 (31 QtBase and six QtMultimedia files,
QtWebEngine left out): the newer APIs are resolved at run time with fallbacks.
08-12 compile Qt against the Windows 7 headers (`_WIN32_WINNT=0x0601`) and fix
what that exposes; 13 replaces `_fstat32`, absent from MSVCRT, in the bundled
Assimp in Qt Quick 3D; 14 drops the `synchronization` and `shcore` import libraries from
Qt's CMake link interface, so no application built with the SDK can import
from a Windows 8 DLL by accident.

The C runtime is MSVCRT because the UCRT is not part of a standard Windows 7
installation. ActiveQt is not built (its `idc` tool would have to run on the
Linux host). Windows on ARM applies the same series; there every run-time
check finds the newer API.

## LLVM migration results

The rebuilt amd64 SDK passed the PE 6.1 audit for all nine executables.
Windows 7 SP1 passed all eight ordinary applications and the strict
C++23 run (25 passed, zero skipped) in a logged-in VMware session.
The same artifacts passed both runs in Windows 11.
The [migration report](../results/qt6-windows-amd64-llvm-migration-20261116.json)
includes the artifact hashes and the earlier background run.

## Previous runtime results

8/8 (508 checks) on Windows 7 SP1 in VMware ([platforms](../platforms.md#qt-685)).
arm64 is built, not run.

## Limits

- Direct3D 11 on real Windows 7 hardware is unchecked (the VM uses the
  software path).
- The audit screens known Windows 8+ imports; it does not replace a review of
  every imported function.

## Sequential LLVM build

The [Windows LLVM build guide](qt6-windows-llvm.md) documents the local
inputs and C++23 checks. The current amd64 SDK builds Qt with Clang and
builds its MSVCRT headers and import libraries from MinGW-w64 source.

### Source override recheck

A fresh amd64 SDK was built with `QT6_SOURCE` pointing to a copy of the
6.8.5 archive with extra xz stream padding and a different SHA-256.
The extracted sources matched the official release, so the verified
native Linux host tools were reused. The repeat build kept the same
SDK image ID and skipped Docker build. All nine executables matched
the manifest and passed the PE 6.1 audit. The strict C++23 run on the
Windows host passed 25 checks with zero skips. The official archive
was restored and its SHA-256 verified after the recheck.
