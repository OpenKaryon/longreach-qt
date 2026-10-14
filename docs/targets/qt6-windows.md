# Qt 6.8.4 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt6-win-amd64` | `qt6-win-amd64-<profile>` | Windows 7 SP1 | LLVM-MinGW 20241217, MSVCRT |
| `make qt6-win-arm64` | `qt6-win-arm64-<profile>` | Windows 10 on ARM | LLVM-MinGW 20241217, UCRT |

Both need the host-tools image (`make qt6-host`), which they use by tag.
`make qt6-win-amd64-examples` builds the test suite against the SDK into
`artifacts/tests-qt6-win-amd64-gpl-enabled/`; `make qt6-win-amd64-audit` screens every EXE for
Windows 8+ loader dependencies (PE subsystem above 6.1, `api-ms-win-*`,
SHCore, WaitOnAddress, GetDpiForMonitor and similar imports).

## Windows 7

`patches/qt6/windows` is the Windows 7 backport. 01-07 are the diffs of
[crystalidea/qt6windows7](https://github.com/crystalidea/qt6windows7) at
`3df3aac7` against pristine 6.8.4 (31 QtBase and six QtMultimedia files,
QtWebEngine left out): the newer APIs are resolved at run time with fallbacks.
08-13 compile Qt against the Windows 7 headers (`_WIN32_WINNT=0x0601`) and fix
what that exposes; 14 replaces `_fstat32`, absent from MSVCRT, in the bundled
Assimp; 15 drops the `synchronization` and `shcore` import libraries from
Qt's CMake link interface, so no application built with the SDK can import
from a Windows 8 DLL by accident.

The C runtime is MSVCRT because the UCRT is not part of a standard Windows 7
installation. ActiveQt is not built (its `idc` tool would have to run on the
Linux host). Windows on ARM applies the same series; there every run-time
check finds the newer API.

## Results

8/8 (508 checks) on Windows 7 SP1 in VMware ([platforms](../platforms.md#qt-684)).
arm64 is built, not run.

## Limits

- Direct3D 11 on real Windows 7 hardware is unchecked (the VM uses the
  software path).
- The audit screens known Windows 8+ imports; it does not replace a review of
  every imported function.
