# Qt 4.8.7 Windows amd64 with LLVM 21.1.8

The static SDK uses upstream Clang, LLD and libc++ 21.1.8 with the
existing Windows XP x64 sysroot and OpenSSL 3.5.7. Linux qmake 2.01a
builds the target libraries and examples. For long object lists, qmake
passes the objects directly to LLD. The repository build exported 11
executables and matched all 37 static archive paths in the GCC SDK.

| Run | Windows 11 x64, build 26200 | Windows 7 SP1 x64, build 7601 (VMware) | Windows XP x64 SP2, build 3790 (VMware) |
|---|---|---|---|
| Standalone C++23 probe | 25 PASS, 0 FAIL, 0 SKIP | 25 PASS, 0 FAIL, 0 SKIP | 25 PASS, 0 FAIL, 0 SKIP |
| Ordinary Qt suite | 8/8 applications, 373 checks passed, 0 failed, 149 optional skips | 8/8 applications, 375 checks passed, 0 failed, 147 optional skips | 8/8 applications, 362 checks passed, 0 failed, 160 optional skips |
| Qt strict C++23 selftest | 25 PASS, 0 FAIL, 0 SKIP | 25 PASS, 0 FAIL, 0 SKIP | 25 PASS, 0 FAIL, 0 SKIP |

All executables use AMD64 PE32+ with subsystem version 5.2 and the
app-local AMD64 Visual C++ 2010 SP1 runtime, version 10.00.40219.325.
The runtime file is supplied separately. The subsystem version records
the intended floor. The [JSON record](qt4-win-amd64-llvm21-xp-20261113.json)
lists the PE imports and file hashes. All imported CRT symbols were found
in the supplied DLL.

On 2026-11-14 a VMware guest installed from the Windows XP Professional
x64 SP2 ISO ran the full test package. The guest reported AMD64, Windows
version 5.2.3790 and Service Pack 2. It compared the 11 executables and
the CRT byte for byte with the verified CD before running them. All three
commands exited with code 0.
[Image catalogue](https://www.heidoc.net/php/myvsdump_details.php?id=P264F12854Ax64Len).

The PE export audit resolved every import for all 11 executables
against the AMD64 system DLLs extracted from that installation ISO
and the app-local Visual C++ runtime. The audit included forwarded
exports.

A local guest package under
`artifacts/qt4-xp-amd64-llvm21/xp-x64-transfer` contains the 11 verified
executables, the app-local runtime and their SHA-256 manifest.
`run-xp-x64.cmd` checks the guest's version and architecture and runs
the standalone probe, strict selftest and ordinary suite in sequence.
The local `xp-x64-guest-tests.iso` contains the verified executables,
runtime and launcher. The launcher compares guest copies byte for byte
with the CD and exports the guest identity, exit codes and test logs to
a FAT12 results floppy. The host verifier checks the XP x64 SP2
identity, both sets of 25 required checks and all eight ordinary apps.
Each launch uses a fresh guest directory. The launcher clears any
previous completion marker and writes a new one only after exporting
the logs. This allows a retry after an interrupted run.

QtScript and QtDeclarative use the JavaScript interpreter. The
JavaScriptCore collector aligns its jump buffer to 16 bytes for the
Windows x64 CRT. The QtGui widget style helper uses the same narrow
Clang optimization workaround as Sarge. The ordinary suite exercised
QtScript's debugger and both affected GUI galleries.

See the [build instructions](../targets/qt4-windows.md#windows-amd64-with-llvm-2118).
